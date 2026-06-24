#!/usr/bin/env bash

# Dynamic Captive Portal Login Script for Rossmann Kunden-WLAN
# Built for portal.eu.mist.com

COOKIE_JAR="/tmp/cookies.txt"
LANDING_PAGE="/tmp/landing_page.html"
AUTH_RESPONSE="/tmp/auth_response.html"

echo "=================================================="
echo "Step 1: Probing for Captive Portal Redirect URL..."
echo "=================================================="

# Probe connectivity endpoint to get effective redirect URL
# -v enables verbose logging
# -L follows redirects
# -w writes out final URL to stdout (captured in variable)
# -o writes response body to LANDING_PAGE
URL_EFFECTIVE=$(curl -v -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{url_effective}" -o "$LANDING_PAGE" "http://detectportal.firefox.com/success.txt")

echo "Redirect URL detected: $URL_EFFECTIVE"

if [ -z "$URL_EFFECTIVE" ] || [ "$URL_EFFECTIVE" = "http://detectportal.firefox.com/success.txt" ]; then
    echo "Already connected to the internet or no redirect occurred."
    ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
fi

echo "=================================================="
echo "Step 2: Parsing Action URL & Hidden Input Fields..."
echo "=================================================="

# Extract action URL from singleAuthForm
ACTION_URL=$(grep -i "singleAuthForm" "$LANDING_PAGE" | grep -oE "action=['\"][^'\"]+['\"]" | head -n1 | sed -E "s/action=['\"]//;s/['\"]//")

# Standardize HTML entities in action URL
ACTION_URL=$(echo "$ACTION_URL" | sed 's/&amp;/\&/g')

if [ -z "$ACTION_URL" ]; then
    echo "Form action not explicitly defined in form tag. Falling back to base URL: $URL_EFFECTIVE"
    ACTION_URL="$URL_EFFECTIVE"
else
    # If ACTION_URL is relative, prefix it with the base domain
    if [[ "$ACTION_URL" = /* ]]; then
        BASE_DOMAIN=$(echo "$URL_EFFECTIVE" | grep -oP '^https?://[^/]+')
        ACTION_URL="${BASE_DOMAIN}${ACTION_URL}"
    fi
fi

echo "Target Form Action URL: $ACTION_URL"

# Parse hidden input elements dynamically
CURL_ARGS=()
while read -r line; do
    [ -z "$line" ] && continue
    NAME=$(echo "$line" | sed -E -n 's/.*name=["\x27\?]([^"\x27\?]+)["\x27\?].*/\1/p')
    VALUE=$(echo "$line" | sed -E -n 's/.*value=["\x27\?]([^"\x27\?]+)["\x27\?].*/\1/p')
    if [ -n "$NAME" ]; then
        echo "Extracted dynamic parameter: $NAME = $VALUE"
        CURL_ARGS+=(--data-urlencode "$NAME=$VALUE")
    fi
done <<< "$(grep -i "<input" "$LANDING_PAGE" | grep -i "hidden")"

# Append static parameters required to simulate accepting the TOS
# tos=true: checking the accept box
# auth_method=passphrase: the submit button's value
echo "Appending static auth parameters (TOS accept & authentication method)..."
CURL_ARGS+=(--data-urlencode "tos=true")
CURL_ARGS+=(--data-urlencode "auth_method=passphrase")

echo "=================================================="
echo "Step 3: Submitting Authentication Request..."
echo "=================================================="

curl -v -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Referer: $URL_EFFECTIVE" \
    -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0" \
    "${CURL_ARGS[@]}" \
    "$ACTION_URL" -o "$AUTH_RESPONSE"

echo "Authentication response page saved to $AUTH_RESPONSE"

echo "=================================================="
echo "Step 4: Verifying Connectivity..."
echo "=================================================="

if ping -c 3 8.8.8.8 >/dev/null; then
    echo "SUCCESS: Authentication successful and internet access verified!"
    exit 0
else
    echo "FAILURE: Still unable to access the internet. Check logs for response page details."
    exit 1
fi
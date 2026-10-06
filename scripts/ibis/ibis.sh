#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# 1. Wait for network readiness
echo "Waiting for IP, Gateway, and DNS..."
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

# Setup cleanups for temporary files
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT

UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Step 1: Attempt to access neverssl.com to trigger redirect..."
# We fetch and save the effective URL to detect where we get redirected.
INITIAL_URL=$(curl -k -A "$UA_BROWSER" -o /dev/null -w "%{redirect_url}" -m 15 "http://neverssl.com")
echo "Redirected to: $INITIAL_URL"

if [ -z "$INITIAL_URL" ]; then
    echo "No redirect detected. Checking if we already have internet..."
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Already connected to the internet!"
        exit 0
    else
        echo "ERROR: No redirect received, but no internet connectivity either."
        exit 1
    fi
fi

# Step 2: Fetch the redirect URL to obtain session cookies and identify the state player API path
echo "Step 2: Accessing landing page to establish cookies..."
EFFECTIVE_URL=$(curl -k -L -A "$UA_BROWSER" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "$INITIAL_URL")
echo "Effective portal URL: $EFFECTIVE_URL"

# Extract the site identifier / path / scenePlayerUri from the HTML if possible.
# The scenePlayerUri can be retrieved from __sceneConfig in the HTML page:
# var __sceneConfig = {"envType":"prod","brandName":"ibis","redirectUrl":"","redirectInterval":"10000","scenePlayerUri":"\/sscp\/iGKzCQzLrzwyM4q1\/",...}
SCENE_PLAYER_URI=$(grep -o '"scenePlayerUri":"[^"]*"' "$HTML_OUT" | head -n 1 | sed 's/"scenePlayerUri":"\(.*\)"/\1/' | sed 's/\\//g')

if [ -z "$SCENE_PLAYER_URI" ]; then
    echo "Warning: scenePlayerUri not found in HTML. Falling back to default '/sscp/iGKzCQzLrzwyM4q1/'"
    SCENE_PLAYER_URI="/sscp/iGKzCQzLrzwyM4q1/"
fi

echo "Extracted scenePlayerUri: $SCENE_PLAYER_URI"

# Extract the base portal host from the effective URL
PORTAL_HOST=$(echo "$EFFECTIVE_URL" | awk -F/ '{print $1"//"$3}')
echo "Portal host is: $PORTAL_HOST"

# Step 3: Call the API to authenticate or accept the terms
# Looking at typical conn4 / Accor portals, they use a JSON-based API at /sscp/xxxx/ or standard forms.
# Specifically, they have a REST endpoint to activate the free wifi session.
# Let's perform a POST login check to activate the free Wi-Fi tier.
LOGIN_URL="${PORTAL_HOST}${SCENE_PLAYER_URI}login"

echo "Step 3: Attempting authentication at API endpoint $LOGIN_URL..."
# We send the request containing accepted terms/free wifi choice
# We pass an empty username and password or standard free tier login attributes.
RESPONSE=$(curl -k -i -A "$UA_BROWSER" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -H "Content-Type: application/json" \
    --data-binary '{"login":"","password":"","selected_tariff":"free","accept_terms":true}' \
    -m 15 "$LOGIN_URL")

echo "Authentication response headers/body:"
echo "$RESPONSE"

# Step 4: Validate and poll for internet connectivity
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds."
exit 1

#!/bin/bash

# Initialize cookie file
COOKIE_FILE="/tmp/cookies.txt"
rm -f "$COOKIE_FILE"

echo "=== STEP 1: Requesting initial URL to trigger captive portal redirection ==="
# We do not use -s/--silent to ensure full debugging visibility on the router
EFFECTIVE_URL=$(curl -v -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -w "%{url_effective}" "http://detectportal.firefox.com/success.txt" -o /tmp/landing.html)

echo "Effective Landing URL: $EFFECTIVE_URL"

# Extract base URL (scheme + domain) dynamically to satisfy Rule 6
BASE_URL=$(echo "$EFFECTIVE_URL" | grep -oE '^(https?://[^/]+)')
echo "Extracted Base URL: $BASE_URL"

echo "=== STEP 2: Dynamically searching for the 'Get Online' activation URL ==="
# Search for link pattern containing /url/[0-9]+
GET_ONLINE_PATH=$(grep -oE "href=['\"][^'\"]+/url/[0-9]+" /tmp/landing.html | sed -E "s/href=['\"]//g" | head -n 1)

if [ -z "$GET_ONLINE_PATH" ]; then
    echo "ERROR: Could not find the 'Get Online' activation URL in the portal HTML!"
    echo "Dumping HTML for debugging:"
    cat /tmp/landing.html
    exit 1
fi

echo "Found raw path: $GET_ONLINE_PATH"

# Construct absolute URL if relative
if [[ ! "$GET_ONLINE_PATH" =~ ^https?:// ]]; then
    if [[ ! "$GET_ONLINE_PATH" =~ ^/ ]]; then
        GET_ONLINE_PATH="/$GET_ONLINE_PATH"
    fi
    GET_ONLINE_URL="${BASE_URL}${GET_ONLINE_PATH}"
else
    GET_ONLINE_URL="$GET_ONLINE_PATH"
fi

echo "Target Activation URL: $GET_ONLINE_URL"

echo "=== STEP 3: Requesting the activation URL to authenticate ==="
RESPONSE_CODE=$(curl -v -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -w "%{http_code}" "$GET_ONLINE_URL" -o /tmp/activation_result.html)
echo "Activation HTTP Response Code: $RESPONSE_CODE"

echo "=== STEP 4: Optionally triggering drift_time_204 context (optional backup) ==="
DRIFT_URL="${BASE_URL}/service-platform/drift_time_204"
echo "Requesting drift time check: $DRIFT_URL"
curl -v -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L "$DRIFT_URL"

echo "=== STEP 5: Verifying network connectivity ==="
if ping -c 3 8.8.8.8 >/dev/null; then
    echo "SUCCESS: Internet is connected!"
    exit 0
else
    echo "FAILURE: Still no internet connectivity."
    exit 1
fi
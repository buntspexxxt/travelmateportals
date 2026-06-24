#!/bin/bash

# Define cookie file
COOKIE_JAR="/tmp/cookies.txt"

# 1. Probe connectivity/redirect to get LANDING_URL and the initial cookies.
echo "=== Step 1: Probing connectivity to trigger captive portal redirect ==="
LANDING_URL=$(curl -v -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -w "%{url_effective}" -o /tmp/landing.html "http://neverssl.com")

echo "Effective Landing URL: $LANDING_URL"
echo "=== Landing HTML saved to /tmp/landing.html ==="

# Extract Base URL dynamically
BASE_URL=$(echo "$LANDING_URL" | grep -oE "https?://[^/]+")
echo "Base URL extracted: $BASE_URL"

# Extract the 'Get Online' or similar URL path
echo "=== Step 2: Extracting the 'Get Online' activation URL from HTML ==="
GET_ONLINE_PATH=$(grep -oE "href=['\"][^'\"]*service-platform/url/[0-9]+" /tmp/landing.html | head -n 1 | sed -E "s/href=['\"]//")

if [ -z "$GET_ONLINE_PATH" ]; then
    echo "Warning: Specific 'service-platform/url/' path not found. Trying fallback regex..."
    GET_ONLINE_PATH=$(grep -oE "href=['\"][^'\"]*/url/[0-9]+" /tmp/landing.html | head -n 1 | sed -E "s/href=['\"]//")
fi

if [ -z "$GET_ONLINE_PATH" ]; then
    echo "Error: Could not find Get Online URL in HTML. Printing HTML content for debugging:"
    cat /tmp/landing.html
    exit 1
fi

echo "Extracted Path: $GET_ONLINE_PATH"

# Build target URL
if [[ "$GET_ONLINE_PATH" == http* ]]; then
    TARGET_URL="$GET_ONLINE_PATH"
else
    # Remove leading slash if any
    GET_ONLINE_PATH=$(echo "$GET_ONLINE_PATH" | sed 's|^/||')
    TARGET_URL="${BASE_URL}/${GET_ONLINE_PATH}"
fi

echo "Target Activation URL: $TARGET_URL"

# 3. Access the activation URL to finalize authentication
echo "=== Step 3: Fetching the activation URL to authenticate ==="
RESPONSE=$(curl -v -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -w "\nHTTP Status: %{http_code}\n" "$TARGET_URL")

echo "Response from activation request:"
echo "$RESPONSE"

# 4. Final check
echo "=== Step 4: Checking internet connectivity ==="
if ping -c 3 8.8.8.8 >/dev/null; then
    echo "Internet access is active!"
    exit 0
else
    echo "Internet access is STILL DOWN!"
    exit 1
fi
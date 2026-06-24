#!/usr/bin/env bash
set -e

echo "=== Starting Captive Portal Login for 'mycloud_service_thecloud_eu' ==="

COOKIE_JAR="/tmp/cookies.txt"
LANDING_FILE="/tmp/landing.html"
RESULT_FILE="/tmp/result.html"

echo "Step 1: Attempting to connect to http://1.1.1.1/ to trigger captive portal redirect..."
EFFECTIVE_URL=$(curl -v -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -w "%{url_effective}" -o "$LANDING_FILE" "http://1.1.1.1/")

echo "Effective Landing URL: $EFFECTIVE_URL"
echo "Saved cookies to $COOKIE_JAR"

echo "Step 2: Parsing Base URL and 'Get Online' link from the landing page..."
BASE_URL=$(echo "$EFFECTIVE_URL" | grep -oE "https?://[^/]+")
echo "Extracted Base URL: $BASE_URL"

# Extracting the Get Online href dynamically from the landing HTML
GET_ONLINE_PATH=$(grep -B 5 -i "Get Online" "$LANDING_FILE" | grep -oE "href=['\"][^'\"]+['\"]" | head -n 1 | sed -E "s/href=['\"]([^'\"]+)['\"]/\1/")

if [ -z "$GET_ONLINE_PATH" ]; then
    echo "ERROR: Could not find 'Get Online' link on the landing page!"
    echo "Page content preview:"
    head -n 50 "$LANDING_FILE"
    exit 1
fi

echo "Extracted Path: $GET_ONLINE_PATH"

# Build absolute URL
if [[ "$GET_ONLINE_PATH" != http* ]]; then
    if [[ "$GET_ONLINE_PATH" != /* ]]; then
        GET_ONLINE_PATH="/$GET_ONLINE_PATH"
    fi
    GET_ONLINE_URL="${BASE_URL}${GET_ONLINE_PATH}"
else
    GET_ONLINE_URL="$GET_ONLINE_PATH"
fi

echo "Constructed Activation URL: $GET_ONLINE_URL"

echo "Step 3: Triggering Activation/Get Online request..."
curl -v -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -o "$RESULT_FILE" "$GET_ONLINE_URL"

echo "Activation request completed. Checking final connectivity..."
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "SUCCESS: Internet is connected!"
    exit 0
else
    echo "FAILED: Still no internet access."
    exit 1
fi
#!/bin/bash

# Configuration
COOKIE_JAR="/tmp/cookies.txt"
PORTAL_HTML_FILE="/tmp/portal.html"

# Ensure clean state
rm -f "$COOKIE_JAR" "$PORTAL_HTML_FILE"

echo "=================================================="
echo "STEP 1: Triggering initial redirect from http://1.1.1.1/"
echo "=================================================="
PORTAL_URL=$(curl -v -o "$PORTAL_HTML_FILE" -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -w "%{url_effective}" "http://1.1.1.1/")

echo "Effective Portal URL: $PORTAL_URL"

if [ ! -f "$PORTAL_HTML_FILE" ]; then
    echo "ERROR: Failed to retrieve Portal HTML!"
    exit 1
fi

echo "=================================================="
echo "STEP 2: Extracting 'Get Online' Link dynamically"
echo "=================================================="
GET_ONLINE_URL=$(grep -oE "href=['\"][^'\"]*/service-platform/url/[0-9]+" "$PORTAL_HTML_FILE" | head -n 1 | sed -E "s/href=['\"]//")

echo "Extracted 'Get Online' URL path: $GET_ONLINE_URL"

if [ -z "$GET_ONLINE_URL" ]; then
    echo "ERROR: Could not find 'Get Online' activation URL in the HTML page!"
    exit 1
fi

# Handle relative URLs if any
if [[ ! "$GET_ONLINE_URL" =~ ^https?:// ]]; then
    echo "URL is relative. Resolving base host from the portal landing page URL..."
    BASE_URL=$(echo "$PORTAL_URL" | grep -oE '^https?://[^/]+')
    GET_ONLINE_URL="${BASE_URL}${GET_ONLINE_URL}"
    echo "Resolved absolute URL: $GET_ONLINE_URL"
fi

echo "=================================================="
echo "STEP 3: Sending request to 'Get Online' URL"
echo "=================================================="
RESPONSE=$(curl -v -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$GET_ONLINE_URL")

echo "Response Output:"
echo "$RESPONSE"

echo "=================================================="
echo "STEP 4: Performing Connectivity Check"
echo "=================================================="
if ping -c 3 8.8.8.8 >/dev/null; then
    echo "SUCCESS: Internet connection is now active!"
    exit 0
else
    echo "FAILED: No active internet connection found."
    exit 1
fi
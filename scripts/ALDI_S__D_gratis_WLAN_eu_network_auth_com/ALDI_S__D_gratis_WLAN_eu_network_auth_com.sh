#!/bin/bash

# Configuration
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_JAR="/tmp/aldi_cookies.txt"
HEADERS_INITIAL="/tmp/aldi_headers_initial.txt"
HEADERS_LANDING_HEAD="/tmp/aldi_headers_landing_head.txt"

echo "Starting ALDI SÜD WLAN login script..."
echo "User-Agent: $USER_AGENT"
echo "Cookie Jar: $COOKIE_JAR"

# Step 1: Trigger initial redirect and capture the landing page URL
echo ""
echo "--- Step 1: Triggering initial redirect to find the captive portal landing page ---"
echo "Making a GET request to http://detectportal.firefox.com/success.txt to trigger the redirect."
echo "Capturing Location header from the response."
INITIAL_RESPONSE=$(curl -A "$USER_AGENT" -L -v -D "$HEADERS_INITIAL" -o /dev/null http://detectportal.firefox.com/success.txt 2>&1)
CURL_STATUS=$?

if [ "$CURL_STATUS" -ne 0 ]; then
    echo "ERROR: Initial curl request failed with status $CURL_STATUS."
    echo "Curl output: $INITIAL_RESPONSE"
    exit 1
fi

LANDING_URL=$(grep -i '^Location:' "$HEADERS_INITIAL" | tail -n 1 | sed 's/^Location: //i' | tr -d '\r
')

if [ -z "$LANDING_URL" ]; then
    echo "ERROR: Could not extract LANDING_URL from initial redirect headers."
    cat "$HEADERS_INITIAL"
    exit 1
fi

echo "Successfully captured LANDING_URL: $LANDING_URL"

# Extract base domain and splash path dynamically
BASE_DOMAIN=$(echo "$LANDING_URL" | sed -E 's|(https?:\/\/[^\/]+).*|\1|')
SPLASH_PATH=$(echo "$LANDING_URL" | sed -E 's|https?:\/\/[^\/]+(\/splash\/[^?]+).*|\1|') # Adjusted regex to capture path up to '?'

if [ -z "$BASE_DOMAIN" ] || [ -z "$SPLASH_PATH" ]; then
    echo "ERROR: Could not extract BASE_DOMAIN or SPLASH_PATH from LANDING_URL."
    echo "Base Domain: '$BASE_DOMAIN', Splash Path: '$SPLASH_PATH'"
    exit 1
fi
echo "Extracted BASE_DOMAIN: $BASE_DOMAIN"
echo "Extracted SPLASH_PATH: $SPLASH_PATH"

# Step 2: GET request to the landing page to establish cookies and fetch content
echo ""
echo "--- Step 2: Getting the captive portal landing page content and setting cookies ---"
echo "Making a GET request to $LANDING_URL"
LANDING_PAGE_CONTENT=$(curl -A "$USER_AGENT" -v -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$LANDING_URL" 2>&1)
CURL_STATUS=$?

if [ "$CURL_STATUS" -ne 0 ]; then
    echo "ERROR: GET request to landing page failed with status $CURL_STATUS."
    echo "Curl output: $LANDING_PAGE_CONTENT"
    exit 1
fi
echo "GET request to landing page successful."

# Step 3: Simulate JS HEAD request to landing page to get 'Continue-Url' header
echo ""
echo "--- Step 3: Simulating JavaScript HEAD request to extract dynamic 'Continue-Url' ---"
echo "Making a HEAD request to $LANDING_URL to get the 'Continue-Url' header, as seen in the JavaScript."
HEAD_RESPONSE=$(curl -A "$USER_AGENT" -v -I -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$LANDING_URL" -o "$HEADERS_LANDING_HEAD" 2>&1)
CURL_STATUS=$?

if [ "$CURL_STATUS" -ne 0 ]; then
    echo "ERROR: HEAD request to landing page failed with status $CURL_STATUS."
    echo "Curl output: $HEAD_RESPONSE"
    echo "Headers captured to $HEADERS_LANDING_HEAD:"
    cat "$HEADERS_LANDING_HEAD"
    exit 1
fi
echo "HEAD request to landing page successful. Headers saved to $HEADERS_LANDING_HEAD."

FINAL_CONTINUE_URL=$(grep -i '^Continue-Url:' "$HEADERS_LANDING_HEAD" | tail -n 1 | sed 's/^Continue-Url: //i' | tr -d '\r
')

if [ -z "$FINAL_CONTINUE_URL" ]; then
    echo "WARNING: 'Continue-Url' header not found in HEAD response. This might cause the login to fail."
    echo "Falling back to 'https://www.aldi-sued.de' based on HTML anchor tag, but this might not work reliably."
    FINAL_CONTINUE_URL="https%3A%2F%2Fwww.aldi-sued.de" # URL-encoded www.aldi-sued.de
fi

echo "Extracted FINAL_CONTINUE_URL: $FINAL_CONTINUE_URL"

# Step 4: Perform the grant request to authorize access
echo ""
echo "--- Step 4: Performing the final grant request ---"
GRANT_URL="${BASE_DOMAIN}${SPLASH_PATH}/grant?continue_url=${FINAL_CONTINUE_URL}"
echo "Making a GET request to the GRANT_URL: $GRANT_URL"

GRANT_RESPONSE=$(curl -A "$USER_AGENT" -v -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$GRANT_URL" 2>&1)
CURL_STATUS=$?

if [ "$CURL_STATUS" -ne 0 ]; then
    echo "ERROR: Grant request failed with status $CURL_STATUS."
    echo "Curl output: $GRANT_RESPONSE"
    exit 1
fi
echo "Grant request completed successfully. This usually indicates successful authentication."

# Step 5: Clean up temporary files
echo ""
echo "--- Step 5: Cleaning up temporary files ---"
rm -f "$COOKIE_JAR" "$HEADERS_INITIAL" "$HEADERS_LANDING_HEAD"
echo "Temporary files removed."

# Step 6: Connectivity Check
echo ""
echo "--- Step 6: Performing connectivity check ---"
echo "Pinging 8.8.8.8 to verify internet connectivity."
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "Connectivity check successful! Internet access is likely granted."
    exit 0
else
    echo "Connectivity check failed. Internet access might not be granted."
    exit 1
fi
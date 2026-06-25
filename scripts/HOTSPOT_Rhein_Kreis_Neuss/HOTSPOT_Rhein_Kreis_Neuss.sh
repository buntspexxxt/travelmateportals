#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/wifi_login_cookies.txt"
INITIAL_PROBE_URL="http://connectivitycheck.gstatic.com/generate_204"

# --- Logging Function ---
log_step() {
    echo "-- $(date '+%Y-%m-%d %H:%M:%S') --"
    echo "STEP: $1"
    echo "--------------------------------------------------------------------------------"
}

# --- Cleanup previous cookies ---
log_step "Cleaning up previous cookie file if it exists: $COOKIE_FILE"
rm -f "$COOKIE_FILE" || true
echo "Cleanup complete."

# 1. Simulate initial probe request to get the captive portal redirect URL
log_step "1. Performing initial probe request to '$INITIAL_PROBE_URL' to capture the captive portal redirect URL."
echo "Curl command: curl -v -A \"$USER_AGENT\" --max-redirs 0 \"$INITIAL_PROBE_URL\""
INITIAL_RESPONSE=$(curl -v -A "$USER_AGENT" --max-redirs 0 "$INITIAL_PROBE_URL" 2>&1)
CURL_STATUS=$?
echo "Curl exit status: $CURL_STATUS"
echo "--- Initial Probe Response (verbose) ---"
echo "$INITIAL_RESPONSE"
echo "----------------------------------------"

if [ "$CURL_STATUS" -ne 0 ]; then
    echo "ERROR: Initial curl probe failed with status $CURL_STATUS. Exiting."
    exit 1
fi

LANDING_URL=$(echo "$INITIAL_RESPONSE" | grep -i Location: | awk '{print $NF}' | tr -d '\r')

if [ -z "$LANDING_URL" ]; then
    echo "ERROR: Could not extract LANDING_URL from initial probe response. Exiting."
    exit 1
fi
echo "Extracted LANDING_URL: $LANDING_URL"

# 2. Extract base path prefix from the LANDING_URL
log_step "2. Extracting the base path prefix from the LANDING_URL."
# Example: https://eu.network-auth.com/splash/bs-qtcsd.7.1097/
# Using regex to get the part before the query string, and specific to the known pattern
BASE_PATH_PREFIX=$(echo "$LANDING_URL" | grep -oE 'https?://[^/]+/splash/[^/]+/[^/]+/' | head -n 1)

if [ -z "$BASE_PATH_PREFIX" ]; then
    echo "ERROR: Could not extract BASE_PATH_PREFIX from LANDING_URL. Exiting."
    exit 1
fi
echo "Extracted BASE_PATH_PREFIX: $BASE_PATH_PREFIX"

# 3. Perform a HEAD request to the LANDING_URL to get the 'Continue-Url' header, saving cookies
# The JavaScript makes a HEAD request to window.location to dynamically get the 'Continue-Url'.
log_step "3. Performing a HEAD request to '$LANDING_URL' to extract the 'Continue-Url' header."
echo "Curl command: curl -v -I -A \"$USER_AGENT\" -c \"$COOKIE_FILE\" -b \"$COOKIE_FILE\" \"$LANDING_URL\""
HEAD_RESPONSE=$(curl -v -I -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$LANDING_URL" 2>&1)
CURL_STATUS=$?
echo "Curl exit status: $CURL_STATUS"
echo "--- HEAD Request Response (verbose) ---"
echo "$HEAD_RESPONSE"
echo "----------------------------------------"

if [ "$CURL_STATUS" -ne 0 ]; then
    echo "ERROR: HEAD request to landing page failed with status $CURL_STATUS. Exiting."
    exit 1
fi

DYNAMIC_CONTINUE_URL=$(echo "$HEAD_RESPONSE" | grep -i "Continue-Url:" | sed -E 's/.*Continue-Url: (.*)/\1/' | tr -d '\r')

if [ -z "$DYNAMIC_CONTINUE_URL" ]; then
    echo "ERROR: Could not extract DYNAMIC_CONTINUE_URL from HEAD request response. Exiting."
    exit 1
fi
echo "Extracted DYNAMIC_CONTINUE_URL: $DYNAMIC_CONTINUE_URL"

# 4. Construct the final grant URL
log_step "4. Constructing the final grant URL."
# The JavaScript constructs the grant URL using the base path and the dynamically fetched Continue-Url.
FINAL_GRANT_URL="${BASE_PATH_PREFIX}grant?continue_url=${DYNAMIC_CONTINUE_URL}"
echo "Constructed FINAL_GRANT_URL: $FINAL_GRANT_URL"

# 5. Make the GET request to the final grant URL to complete the login, using cookies
# Use -L to follow redirects after successful authentication.
log_step "5. Making GET request to the FINAL_GRANT_URL to complete the login."
echo "Curl command: curl -v -L -A \"$USER_AGENT\" -b \"$COOKIE_FILE\" -c \"$COOKIE_FILE\" \"$FINAL_GRANT_URL\""
GRANT_RESPONSE=$(curl -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$FINAL_GRANT_URL" 2>&1)
CURL_STATUS=$?
echo "Curl exit status: $CURL_STATUS"
echo "--- Grant Request Response (verbose) ---"
echo "$GRANT_RESPONSE"
echo "----------------------------------------"

if [ "$CURL_STATUS" -ne 0 ]; then
    echo "ERROR: Grant request failed with status $CURL_STATUS. Exiting."
    exit 1
fi

# 6. Final connectivity check
log_step "6. Performing final connectivity check by pinging 8.8.8.8."
echo "Command: ping -c 3 8.8.8.8"
ping -c 3 8.8.8.8
PING_STATUS=$?

if [ "$PING_STATUS" -eq 0 ]; then
    echo "Connectivity check successful. Portal login likely successful."
    rm -f "$COOKIE_FILE" # Clean up cookie file on success
    exit 0
else
    echo "Connectivity check failed. Portal login may not have been successful."
    echo "Please check the curl outputs for errors and ensure the portal page logic hasn't changed."
    rm -f "$COOKIE_FILE" # Clean up cookie file on failure
    exit 1
fi

#!/bin/bash

# --- Configuration ---
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_JAR="/tmp/conn4_cookies.txt"
INITIAL_CHECK_URL="http://detectportal.firefox.com/success.txt"

# --- Logging function ---
log_step() {
    echo "=========================================================="
    echo "STEP: $1"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================================="
}

log_info() {
    echo "INFO: $1"
}

log_error() {
    echo "ERROR: $1" >&2
}

# --- Main Script ---

# 1. Initial connectivity check to trigger portal redirect
log_step "1. Performing initial connectivity check to trigger captive portal redirect..."
echo "Requesting: ${INITIAL_CHECK_URL}"
# Use -L to follow redirects, -D to save headers to stdout, -o /dev/null to discard body
# We need to capture the *effective URL* which contains the dynamic parameters.
# The effective URL is the final URL after all redirects.
INITIAL_REDIRECT_RESPONSE=$(curl -A "${USER_AGENT}" -L -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -o /dev/null -w "%{url_effective}\
%{http_code}\
" "${INITIAL_CHECK_URL}" -k 2>&1)
CURL_EXIT_CODE=$?

if [ "$CURL_EXIT_CODE" -ne 0 ]; then
    log_error "Curl command failed with exit code $CURL_EXIT_CODE during initial check."
    echo "Curl verbose output:"
    curl -v -A "${USER_AGENT}" -L -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" "${INITIAL_CHECK_URL}" -k
    exit 1
fi

EFFECTIVE_URL=$(echo "$INITIAL_REDIRECT_RESPONSE" | head -n 1)
HTTP_STATUS=$(echo "$INITIAL_REDIRECT_RESPONSE" | tail -n 1)

echo "Initial request to ${INITIAL_CHECK_URL} completed."
echo "HTTP Status Code: ${HTTP_STATUS}"
echo "Effective URL after redirects: ${EFFECTIVE_URL}"

if [ -z "$EFFECTIVE_URL" ] || [[ ! "$EFFECTIVE_URL" =~ ^https://.*rdr\\.conn4\\.com/ident.* ]]; then
    log_error "Did not receive expected redirect URL to conn4.com ident page. Effective URL: ${EFFECTIVE_URL}"
    echo "This might indicate the portal is already open or the network is not redirecting as expected."
    exit 1
fi

# 2. Extract dynamic parameters from the effective URL
log_step "2. Extracting dynamic parameters from the effective URL..."
BASE_DOMAIN=$(echo "$EFFECTIVE_URL" | sed -E 's/https?:\\/\\/(.+)\\/ident\\?.*/\\1/')
CLIENT_IP=$(echo "$EFFECTIVE_URL" | grep -oP 'client_ip=\\K[^&]*')
CLIENT_MAC=$(echo "$EFFECTIVE_URL" | grep -oP 'client_mac=\\K[^&]*')
SITE_ID=$(echo "$EFFECTIVE_URL" | grep -oP 'site_id=\\K[^&]*')
SIGNATURE=$(echo "$EFFECTIVE_URL" | grep -oP 'signature=\\K[^&]*')
LOGGEDIN=$(echo "$EFFECTIVE_URL" | grep -oP 'loggedin=\\K[^&]*')
REMEMBERED_MAC=$(echo "$EFFECTIVE_URL" | grep -oP 'remembered_mac=\\K[^&]*')

echo "Extracted Base Domain: ${BASE_DOMAIN}"
echo "Extracted Client IP: ${CLIENT_IP}"
echo "Extracted Client MAC: ${CLIENT_MAC}"
echo "Extracted Site ID: ${SITE_ID}"
echo "Extracted Signature: ${SIGNATURE}"
echo "Extracted Logged In: ${LOGGEDIN}"
echo "Extracted Remembered MAC: ${REMEMBERED_MAC}"

if [ -z "$BASE_DOMAIN" ] || [ -z "$CLIENT_MAC" ] || [ -z "$SIGNATURE" ]; then
    log_error "Failed to extract one or more critical dynamic parameters. Exiting."
    exit 1
fi

# 3. Make GET request to the ident URL to load the main portal page and capture its content and cookies
log_step "3. Making GET request to the ident URL and following redirect to the main portal page..."
MAIN_PORTAL_URL="https://${BASE_DOMAIN}/ident?client_ip=${CLIENT_IP}&client_mac=${CLIENT_MAC}&site_id=${SITE_ID}&signature=${SIGNATURE}&loggedin=${LOGGEDIN}&remembered_mac=${REMEMBERED_MAC}"
echo "Requesting: ${MAIN_PORTAL_URL}"

# We are following the redirect to the main portal page (https://BASE_DOMAIN/#)
# Capture the full response for debugging and discard body, only saving cookies
curl_output=$(curl -v -A "${USER_AGENT}" -L -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -o /dev/null -w "%{url_effective}\
%{http_code}\
" "${MAIN_PORTAL_URL}" -k 2>&1)
CURL_EXIT_CODE=$?

if [ "$CURL_EXIT_CODE" -ne 0 ]; then
    log_error "Curl command failed with exit code $CURL_EXIT_CODE when requesting main portal page."
    echo "Curl verbose output:"
    echo "$curl_output"
    exit 1
fi

MAIN_PORTAL_EFFECTIVE_URL=$(echo "$curl_output" | tail -n 2 | head -n 1)
MAIN_PORTAL_HTTP_STATUS=$(echo "$curl_output" | tail -n 1)

echo "Request to ${MAIN_PORTAL_URL} completed."
echo "HTTP Status Code for final page: ${MAIN_PORTAL_HTTP_STATUS}"
echo "Effective URL for final page: ${MAIN_PORTAL_EFFECTIVE_URL}"
echo "Cookies saved to: ${COOKIE_JAR}"
echo "--- Current Cookies ---"
cat "${COOKIE_JAR}" || echo "No cookies found."
echo "-----------------------"

# At this point, the initial HTML is loaded, but it's a JavaScript loader.
log_step "4. Analyzing the main portal page for login mechanism."
log_error "The captive portal at ${MAIN_PORTAL_EFFECTIVE_URL} heavily relies on client-side JavaScript."
log_error "The HTML indicates a 'scene loader' (conn4.startSceneLoader) is used to dynamically load the actual login content."
log_error "This typically means the login form, if any, is rendered by JavaScript after the initial page loads."
log_error "Therefore, a simple cURL script cannot reliably interact with it to complete the login."
log_error "Confidence: red. Manual intervention or a headless browser solution is required."

# The script exits with 1 because it cannot perform the login with curl.
exit 1

# Connectivity check (will not be reached in this "red" scenario)
log_step "5. Performing final connectivity check to verify internet access."
if ping -c 3 8.8.8.8 >/dev/null; then
    log_info "Connectivity check successful. Internet access confirmed."
    exit 0
else
    log_error "Connectivity check failed. Internet access NOT confirmed."
    exit 1
fi
#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"

# Log file location
LOG_FILE="/tmp/captive_portal_login.log"

# Cleanup old log file if it exists
if [ -f "$LOG_FILE" ]; then
    rm "$LOG_FILE"
fi

echo "Starting captive portal login script for Commerzbank_Wifi2_0_ag02w03_agni_arista_io" | tee -a "$LOG_FILE"

# Wait for network and DNS to be ready
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# --- Step 1: Initial Redirect --- 
# The initial access likely redirects to the login page.
# We will use curl to follow redirects and get the final landing page.
# We will use a temporary cookie file to maintain session information.

COOKIE_FILE=$(mktemp)
echo "Creating temporary cookie file: $COOKIE_FILE" | tee -a "$LOG_FILE"

echo "Fetching initial landing page and following redirects..." | tee -a "$LOG_FILE"

# Using --location to follow redirects and -w "%{url_effective}" to get the final URL
REDIRECT_URL=$(curl -k -L -c "$COOKIE_FILE" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%{url_effective}" -o /dev/null "http://detectportal.firefox.com/success.txt")

REDIRECT_STATUS=$?

if [ $REDIRECT_STATUS -ne 0 ]; then
    echo "ERROR: Failed to get initial redirect URL. Curl exit code: $REDIRECT_STATUS" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Initial redirect completed. Effective URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

# --- Step 2: Fetching the Login Page HTML --- 
# The HTML content of the login page is needed to find any hidden form fields.

echo "Fetching the login page HTML from: $REDIRECT_URL" | tee -a "$LOG_FILE"

LOGIN_PAGE_HTML=$(curl -k -s -b "$COOKIE_FILE" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "$REDIRECT_URL")

LOGIN_PAGE_STATUS=$?

if [ $LOGIN_PAGE_STATUS -ne 0 ]; then
    echo "ERROR: Failed to fetch login page HTML. Curl exit code: $LOGIN_PAGE_STATUS" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Login page HTML fetched successfully." | tee -a "$LOG_FILE"

# --- Step 3: Parsing HTML for Login Form Data --- 
# The HTML indicates a React application. Modern portals often use JavaScript
# to dynamically generate form data or use APIs. However, since we don't have
# specific JavaScript execution capabilities with curl, we look for common form fields.
# Based on the provided HTML, there's no visible form. The `robots.txt.html` and `index.html`
# point to a React app that likely handles login via an API call or dynamic form submission.
# The `main.7ee2e305.js` file is very large and likely contains the logic.
# Without the ability to execute JS, we need to infer the POST data structure.
# The `__Host-Antaraai-Portal` cookie suggests a portal system.
# Given the redirect URL structure and cookie, it's likely a standard captive portal
# that requires just an acknowledgement or a POST to a specific endpoint.

# We'll attempt a POST request to the base path of the redirect URL, assuming it's a
# common pattern for accepting terms or logging in without credentials.
# We extract the base URL from the REDIRECT_URL.
BASE_URL=$(echo "$REDIRECT_URL" | sed -E 's/(https?://[^/]+)/.*/\1/')
LOGIN_ENDPOINT="${BASE_URL}/login/"

# Attempting a POST request with minimal data, as no form fields are present.
# This is a common pattern for free WiFi portals where accepting terms is enough.
# We'll assume no username/password are required and just submit an empty payload.

echo "Attempting to POST to login endpoint: $LOGIN_ENDPOINT" | tee -a "$LOG_FILE"

POST_RESPONSE=$(curl -k -s -b "$COOKIE_FILE" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%{http_code}" -o /dev/null -w "%\{http_code}" -X POST -d "" "$LOGIN_ENDPOINT")

POST_STATUS=$?

if [ $POST_STATUS -ne 0 ]; then
    echo "ERROR: POST request to login endpoint failed. Curl exit code: $POST_STATUS" | tee -a "$LOG_FILE"
    exit 1
fi


echo "POST request to $LOGIN_ENDPOINT completed with HTTP status code: $POST_RESPONSE" | tee -a "$LOG_FILE"

# --- Step 4: Verifying Internet Connectivity --- 
# Even if the portal responds successfully, we need to verify actual internet access.

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")

if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi

#!/bin/bash

# --- Configuration ---
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/accor_conn4_cookies.txt"
LOG_FILE="/tmp/accor_conn4_login.log"

# Clear previous logs and cookie file
> "$LOG_FILE"
echo "--- Starting ibis_accor_conn4_com login script ---" | tee -a "$LOG_FILE"
echo "User-Agent: $USER_AGENT" | tee -a "$LOG_FILE"
echo "Cookie File: $COOKIE_FILE" | tee -a "$LOG_FILE"
rm -f "$COOKIE_FILE"

# Function to log and exit on error
log_and_exit() {
    echo "ERROR: $1" | tee -a "$LOG_FILE"
    exit 1
}

# --- Step 1: Initial Probe and Parameter Extraction ---
echo "" | tee -a "$LOG_FILE"
echo "STEP 1: Probing Firefox portal detection URL to get initial redirect and parameters." | tee -a "$LOG_FILE"
echo "Requesting: http://detectportal.firefox.com/success.txt" | tee -a "$LOG_FILE"

# Use curl -v to capture redirects and headers
# Store verbose output in a temporary file to parse later
CURL_OUTPUT_STEP1=$(curl -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" "http://detectportal.firefox.com/success.txt" 2>&1)
CURL_STATUS_STEP1=$?
echo "$CURL_OUTPUT_STEP1" | tee -a "$LOG_FILE"

if [ $CURL_STATUS_STEP1 -ne 0 ]; then
    log_and_exit "Curl command failed for initial probe (Step 1). HTTP Status: $CURL_STATUS_STEP1"
fi

# Extract the effective URL after redirects
# This will be the accor.conn4.com/ident?... URL
EFFECTIVE_URL=$(echo "$CURL_OUTPUT_STEP1" | grep -oP '(?<=^< Location: |^< location: ).*' | tail -1 | tr -d '\\r')
if [ -z "$EFFECTIVE_URL" ]; then
    log_and_exit "Could not extract effective URL from initial probe output."
fi
echo "Effective URL after redirects (ident URL): $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extract base domain from EFFECTIVE_URL
BASE_DOMAIN=$(echo "$EFFECTIVE_URL" | awk -F'[/:]' '{print $4}')
BASE_DOMAIN_FULL=$(echo "$EFFECTIVE_URL" | awk -F'?' '{print $1}' | awk -F'//' '{print $2}' | sed 's/\\/#//g')
echo "Base Domain: $BASE_DOMAIN" | tee -a "$LOG_FILE"
echo "Base Domain Full (for origin field): $BASE_DOMAIN_FULL" | tee -a "$LOG_FILE"

# Extract parameters from the ident URL (the effective URL)
QUERY_STRING=$(echo "$EFFECTIVE_URL" | grep -oP '\\?.*')
if [ -z "$QUERY_STRING" ]; then
    log_and_exit "Could not extract query string from effective URL."
fi
echo "Query String: $QUERY_STRING" | tee -a "$LOG_FILE"

CLIENT_IP=$(echo "$QUERY_STRING" | grep -oP 'client_ip=\\K[^&]*')
CLIENT_MAC=$(echo "$QUERY_STRING" | grep -oP 'client_mac=\\K[^&]*')
SITE_ID=$(echo "$QUERY_STRING" | grep -oP 'site_id=\\K[^&]*')
SIGNATURE=$(echo "$QUERY_STRING" | grep -oP 'signature=\\K[^&]*')

if [ -z "$CLIENT_IP" ] || [ -z "$CLIENT_MAC" ] || [ -z "$SITE_ID" ] || [ -z "$SIGNATURE" ]; then
    log_and_exit "Missing one or more critical parameters (client_ip, client_mac, site_id, signature) from ident URL."
fi

echo "Extracted client_ip: $CLIENT_IP" | tee -a "$LOG_FILE"
echo "Extracted client_mac: $CLIENT_MAC" | tee -a "$LOG_FILE"
echo "Extracted site_id: $SITE_ID" | tee -a "$LOG_FILE"
echo "Extracted signature: $SIGNATURE" | tee -a "$LOG_FILE"

# --- Step 2: Load Landing Page HTML and Extract scenePlayerUri ---
echo "" | tee -a "$LOG_FILE"
echo "STEP 2: Loading the final landing page HTML to establish cookies and extract scene configuration." | tee -a "$LOG_FILE"
echo "Requesting: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

HTML_RESPONSE=$(curl -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$EFFECTIVE_URL" 2>&1)
CURL_STATUS_STEP2=$?
echo "$HTML_RESPONSE" | tee -a "$LOG_FILE"

if [ $CURL_STATUS_STEP2 -ne 0 ]; then
    log_and_exit "Curl command failed for loading landing page (Step 2). HTTP Status: $CURL_STATUS_STEP2"
fi

# Extract __sceneConfig JSON object from the HTML
SCENE_CONFIG_RAW=$(echo "$HTML_RESPONSE" | grep -oP 'var __sceneConfig = \\{.*?};' | head -1)
if [ -z "$SCENE_CONFIG_RAW" ]; then
    log_and_exit "Could not find '__sceneConfig' in the landing page HTML. This may indicate a change in portal structure or an incomplete response."
fi
echo "Raw Scene Config found: $SCENE_CONFIG_RAW" | tee -a "$LOG_FILE"

# Parse scenePlayerUri from the extracted JSON string
# Remove 'var __sceneConfig = ' prefix and trailing semicolon, then extract the value
SCENE_CONFIG_JSON=$(echo "$SCENE_CONFIG_RAW" | sed 's/^var __sceneConfig = //; s/;$//')
SCENE_PLAYER_URI=$(echo "$SCENE_CONFIG_JSON" | grep -oP '"scenePlayerUri":"\\K[^"]*')
SCENE_PLAYER_URI=$(echo "$SCENE_PLAYER_URI" | sed 's/\\\\//g') # Unescape forward slashes like \\/sscp\\/ -> /sscp/

if [ -z "$SCENE_PLAYER_URI" ]; then
    log_and_exit "Could not extract 'scenePlayerUri' from __sceneConfig. The portal's API endpoint might have changed."
fi

SCENE_PLAYER_URL="https://$BASE_DOMAIN$SCENE_PLAYER_URI"
echo "Extracted scenePlayerUri: $SCENE_PLAYER_URI" | tee -a "$LOG_FILE"
echo "Constructed Scene Player URL for POST: $SCENE_PLAYER_URL" | tee -a "$LOG_FILE"

# --- Step 3: Attempt Login/Activation by POSTing to scenePlayerUri ---
echo "" | tee -a "$LOG_FILE"
echo "STEP 3: Attempting to activate/login by POSTing client data to the Scene Player URL." | tee -a "$LOG_FILE"
echo "This portal is likely a 'click-to-connect' type where initial client parameters are sufficient for activation." | tee -a "$LOG_FILE"

POST_DATA="client_ip=${CLIENT_IP}&client_mac=${CLIENT_MAC}&site_id=${SITE_ID}&signature=${SIGNATURE}&origin=https://${BASE_DOMAIN}"
echo "POST data: $POST_DATA" | tee -a "$LOG_FILE"
echo "Target URL: $SCENE_PLAYER_URL" | tee -a "$LOG_FILE"

LOGIN_RESPONSE=$(curl -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST \\
    -H "Content-Type: application/x-www-form-urlencoded" \\
    -d "$POST_DATA" "$SCENE_PLAYER_URL" 2>&1)
CURL_STATUS_STEP3=$?
echo "$LOGIN_RESPONSE" | tee -a "$LOG_FILE"

if [ $CURL_STATUS_STEP3 -ne 0 ]; then
    log_and_exit "Curl command failed for login/activation (Step 3). HTTP Status: $CURL_STATUS_STEP3. Response indicated failure."
fi

# Check for success indicators (e.g., HTTP 200 OK or a redirect to a non-portal page)
# The previous execution logs show a 200 OK for the landing page. A successful POST might return 200 or 302.
HTTP_STATUS=$(echo "$LOGIN_RESPONSE" | grep -oP '^< HTTP/\S+ \\K[0-9]{3}' | tail -1)
if [[ "$HTTP_STATUS" == 2* ]] || [[ "$HTTP_STATUS" == 3* ]]; then
    echo "Login/activation POST returned HTTP $HTTP_STATUS. Proceeding to connectivity check." | tee -a "$LOG_FILE"
else
    log_and_exit "Login/activation POST returned unexpected HTTP status $HTTP_STATUS. Assuming failure."
fi

# --- Step 4: Connectivity Check ---
echo "" | tee -a "$LOG_FILE"
echo "STEP 4: Performing connectivity check." | tee -a "$LOG_FILE"

if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "Connectivity check successful. Internet access confirmed." | tee -a "$LOG_FILE"
    echo "--- Login script finished successfully ---" | tee -a "$LOG_FILE"
    exit 0
else
    log_and_exit "Connectivity check failed. Internet access not confirmed after login attempt."
fi

#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp) # Create a temporary cookie file

echo "Starting RRX Hotspot Login Process..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP, Gateway, and DNS
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# 2. Fetch initial redirect URL and extract Hotsplots login parameters
echo "Fetching initial redirect URL from neverssl.com (or portal.iob.de fallback)..." | tee -a "$LOG_FILE"

# Helper function to execute curl and capture its effective URL and verbose output
perform_curl_and_log() {
    local url="$1"
    local curl_options="$2"
    local log_prefix="$3"
    local temp_output_file=$(mktemp)

    echo "${log_prefix} Requesting URL: ${url}" | tee -a "$LOG_FILE"
    EFFECTIVE_URL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -o /dev/null -w "%{\url_effective}" "$url" ${curl_options} 2>"$temp_output_file")
    HTTP_STATUS=$(grep "< HTTP" "$temp_output_file" | tail -1 | awk '{print $3}')

    echo "${log_prefix} Effective URL: ${EFFECTIVE_URL}" | tee -a "$LOG_FILE"
    echo "${log_prefix} HTTP Status: ${HTTP_STATUS}" | tee -a "$LOG_FILE"
    echo "${log_prefix} Verbose output:" | tee -a "$LOG_FILE"
    cat "$temp_output_file" | tee -a "$LOG_FILE"
    rm -f "$temp_output_file"
    echo "${EFFECTIVE_URL}"
}

REDIRECT_URL=$(perform_curl_and_log "http://neverssl.com" "" "Initial")

if [ -z "$REDIRECT_URL" ] || ! echo "$REDIRECT_URL" | grep -q "portal.iob.de"; then
    echo "Could not get a valid redirect URL to portal.iob.de from neverssl.com. Trying direct access..." | tee -a "$LOG_FILE"
    REDIRECT_URL=$(perform_curl_and_log "http://portal.iob.de/" "" "Direct Access")
fi

if [ -z "$REDIRECT_URL" ]; then
    echo "ERROR: Failed to get any valid redirect URL. Exiting." | tee -a "$LOG_FILE"
    rm -f "$COOKIE_FILE"
    exit 1
fi

# Extract LOGIN_URL (Hotsplots auth URL) from query string of the final redirect URL
LOGIN_URL_ENCODED=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\([^&]*\).*/\1/p')
LOGIN_URL=$(echo "$LOGIN_URL_ENCODED" | sed 's/%3a/:/g;s/%2f/\//g;s/%26/\&/g;s/%3d/=/g')

if [ -z "$LOGIN_URL" ]; then
    echo "ERROR: Could not extract Hotsplots LOGIN_URL from REDIRECT_URL: $REDIRECT_URL. Exiting." | tee -a "$LOG_FILE"
    rm -f "$COOKIE_FILE"
    exit 1
fi

echo "Extracted Hotsplots URL: $LOGIN_URL" | tee -a "$LOG_FILE"
echo "Final REDIRECT_URL (portal.iob.de): $REDIRECT_URL" | tee -a "$LOG_FILE"

# 3. Access Prelogin (Stage 1) - This simulates clicking the "Online gehen" button on portal.iob.de
# The href of the button is "http://192.168.44.1/prelogin"
PRELOGIN_URL="http://192.168.44.1/prelogin"
echo "Accessing prelogin step: $PRELOGIN_URL" | tee -a "$LOG_FILE"

PRELOGIN_EFFECTIVE_URL=$(perform_curl_and_log "$PRELOGIN_URL" "" "Prelogin")

# The PRELOGIN_EFFECTIVE_URL *should* now be the Hotsplots login page.
# If it's not, we'll fall back to the initially extracted LOGIN_URL.
HOTSPLOTS_LOGIN_PAGE_URL="$PRELOGIN_EFFECTIVE_URL"
if ! echo "$HOTSPLOTS_LOGIN_PAGE_URL" | grep -q "hotsplots.de"; then
    echo "Warning: Prelogin effective URL did not redirect to Hotsplots. Falling back to initially extracted LOGIN_URL: $LOGIN_FILE" | tee -a "$LOG_FILE"
    HOTSPLOTS_LOGIN_PAGE_URL="$LOGIN_URL"
fi


# 4. Get Hotsplots Login Page to extract any hidden form parameters (Stage 2, part 1)
# This GET request is important to ensure we have the correct Hotsplots page context and any specific tokens.
echo "Fetching Hotsplots login page from: $HOTSPLOTS_LOGIN_PAGE_URL" | tee -a "$LOG_FILE"
HOTSPLOTS_HTML=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$HOTSPLOTS_LOGIN_PAGE_URL" 2>&1)
HOTSPLOTS_HTTP_CODE=$(echo "$HOTSPLOTS_HTML" | grep "< HTTP" | tail -1 | awk '{print $3}') # Extract HTTP code from verbose output

echo "Hotsplots Login Page HTTP Code: $HOTSPLOTS_HTTP_CODE" | tee -a "$LOG_FILE"
echo "Hotsplots Login Page HTML fetched (verbose output included above)." | tee -a "$LOG_FILE"

# Parse Hotsplots_HTML for the form action and hidden fields
# The form action for Hotsplots is typically the base URL of the login.php
HOTSPLOTS_FORM_ACTION=$(echo "$HOTSPLOTS_LOGIN_PAGE_URL" | cut -d'?' -f1)
echo "Hotsplots form action URL derived: $HOTSPLOTS_FORM_ACTION" | tee -a "$LOG_FILE"

# Extract parameters from LOGIN_URL query string first
LOGIN_URL_QUERY_STRING=$(echo "$LOGIN_URL" | cut -d'?' -s -f2)

CHALLENGE_QS=$(echo "$LOGIN_URL_QUERY_STRING" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
UAMIP_QS=$(echo "$LOGIN_URL_QUERY_STRING" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT_QS=$(echo "$LOGIN_URL_QUERY_STRING" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
MAC_QS=$(echo "$LOGIN_URL_QUERY_STRING" | sed -n 's/.*mac=\([^&]*\).*/\1/p')
IP_QS=$(echo "$LOGIN_URL_QUERY_STRING" | sed -n 's/.*ip=\([^&]*\).*/\1/p')
CALLED_QS=$(echo "$LOGIN_URL_QUERY_STRING" | sed -n 's/.*called=\([^&]*\).*/\1/p')
NASID_QS=$(echo "$LOGIN_URL_QUERY_STRING" | sed -n 's/.*nasid=\([^&]*\).*/\1/p')
SESSIONID_QS=$(echo "$LOGIN_URL_QUERY_STRING" | sed -n 's/.*sessionid=\([^&]*\).*/\1/p')
USERURL_QS=$(echo "$LOGIN_URL_QUERY_STRING" | sed -n 's/.*userurl=\([^&]*\).*/\1/p')
RES_QS=$(echo "$LOGIN_URL_QUERY_STRING" | sed -n 's/.*res=\([^&]*\).*/\1/p')

# Extract values from Hotsplots HTML form, these will override if found
CHALLENGE_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="challenge"[[:space:]]*value="\([^"]*\)".*/\1/p')
UAMIP_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="uamip"[[:space:]]*value="\([^"]*\)".*/\1/p')
UAMPORT_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="uamport"[[:space:]]*value="\([^"]*\)".*/\1/p')
MAC_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="mac"[[:space:]]*value="\([^"]*\)".*/\1/p')
IP_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="ip"[[:space:]]*value="\([^"]*\)".*/\1/p')
CALLED_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="called"[[:space:]]*value="\([^"]*\)".*/\1/p')
NASID_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="nasid"[[:space:]]*value="\([^"]*\)".*/\1/p')
SESSIONID_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="sessionid"[[:space:]]*value="\([^"]*\)".*/\1/p')
USERURL_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="userurl"[[:space:]]*value="\([^"]*\)".*/\1/p')
RES_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="res"[[:space:]]*value="\([^"]*\)".*/\1/p')
HS_TOKEN_FORM=$(echo "$HOTSPLOTS_HTML" | sed -n 's/.*name="hs_token"[[:space:]]*value="\([^"]*\)".*/\1/p') # Hotsplots-specific token

# Prioritize form values, fallback to query string values
CHALLENGE="${CHALLENGE_FORM:-$CHALLENGE_QS}"
UAMIP="${UAMIP_FORM:-$UAMIP_QS}"
UAMPORT="${UAMPORT_FORM:-$UAMPORT_QS}"
MAC="${MAC_FORM:-$MAC_QS}"
IP="${IP_FORM:-$IP_QS}"
CALLED="${CALLED_FORM:-$CALLED_QS}"
NASID="${NASID_FORM:-$NASID_QS}"
SESSIONID="${SESSIONID_FORM:-$SESSIONID_QS}"
USERURL="${USERURL_FORM:-$USERURL_QS}"
RES="${RES_FORM:-$RES_QS}"
HS_TOKEN="${HS_TOKEN_FORM}" # hs_token is likely only in form

echo "Consolidated Hotsplots parameters:" | tee -a "$LOG_FILE"
echo "  CHALLENGE: $CHALLENGE" | tee -a "$LOG_FILE"
echo "  UAMIP: $UAMIP" | tee -a "$LOG_FILE"
echo "  UAMPORT: $UAMPORT" | tee -a "$LOG_FILE"
echo "  MAC: $MAC" | tee -a "$LOG_FILE"
echo "  IP: $IP" | tee -a "$LOG_FILE"
echo "  CALLED: $CALLED" | tee -a "$LOG_FILE"
echo "  NASID: $NASID" | tee -a "$LOG_FILE"
echo "  SESSIONID: $SESSIONID" | tee -a "$LOG_FILE"
echo "  USERURL: $USERURL" | tee -a "$LOG_FILE"
echo "  RES: $RES" | tee -a "$LOG_FILE"
echo "  HS_TOKEN: $HS_TOKEN" | tee -a "$LOG_FILE"

# Construct POST data. Username and password are empty as per previous script.
POST_DATA="username=&password="

# Add consolidated fields only if they are not empty
[ -n "$CHALLENGE" ] && POST_DATA="${POST_DATA}&challenge=${CHALLENGE}"
[ -n "$UAMIP" ] && POST_DATA="${POST_DATA}&uamip=${UAMIP}"
[ -n "$UAMPORT" ] && POST_DATA="${POST_DATA}&uamport=${UAMPORT}"
[ -n "$MAC" ] && POST_DATA="${POST_DATA}&mac=${MAC}"
[ -n "$IP" ] && POST_DATA="${POST_DATA}&ip=${IP}"
[ -n "$CALLED" ] && POST_DATA="${POST_DATA}&called=${CALLED}"
[ -n "$NASID" ] && POST_DATA="${POST_DATA}&nasid=${NASID}"
[ -n "$SESSIONID" ] && POST_DATA="${POST_DATA}&sessionid=${SESSIONID}"
[ -n "$USERURL" ] && POST_DATA="${POST_DATA}&userurl=${USERURL}"
[ -n "$RES" ] && POST_DATA="${POST_DATA}&res=${RES}"
[ -n "$HS_TOKEN" ] && POST_DATA="${POST_DATA}&hs_token=${HS_TOKEN}"

# Add the 'Login' button parameter as per previous script
POST_DATA="${POST_DATA}&button=Login"

echo "Constructed POST data for Hotsplots: $POST_DATA" | tee -a "$LOG_FILE"

# 5. Final Hotsplots Authorization (Stage 2, part 2)
echo "Performing final auth against Hotsplots form action URL: $HOTSPLOTS_FORM_ACTION" | tee -a "$LOG_FILE"
AUTH_RESPONSE=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -d "$POST_DATA" "$HOTSPLOTS_FORM_ACTION" 2>&1)
AUTH_HTTP_CODE=$(echo "$AUTH_RESPONSE" | grep "< HTTP" | tail -1 | awk '{print $3}')

echo "Auth HTTP Code from Hotsplots: $AUTH_HTTP_CODE" | tee -a "$LOG_FILE"
echo "Auth Response from Hotsplots (verbose output included above): $AUTH_RESPONSE" | tee -a "$LOG_FILE"

# Clean up cookie file
rm -f "$COOKIE_FILE"
echo "Cleaned up cookie file: $COOKIE_FILE" | tee -a "$LOG_FILE"

# 6. Connectivity check
echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{\http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
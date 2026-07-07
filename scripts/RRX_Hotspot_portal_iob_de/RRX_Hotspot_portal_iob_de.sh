#!/bin/bash
# SCRIPT_VERSION="1.0.0"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Login Process..." | tee -a "$LOG_FILE"

# Smart wait loop for network
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

perform_curl() {
    curl -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$@"
}

# Step 1: Trigger the portal
echo "Step 1: Accessing captive portal..." | tee -a "$LOG_FILE"
INITIAL_RESPONSE=$(perform_curl -I "http://neverssl.com" 2>&1)

# Step 2: Extract Hotsplots auth parameters
LOGIN_URL=$(echo "$INITIAL_RESPONSE" | sed -n 's/.*loginurl=\([^&]*\).*/\1/p' | sed 's/%3a/:/g;s/%2f/\//g;s/%26/\&/g;s/%3d/=/g')
echo "Auth URL: $LOGIN_URL" | tee -a "$LOG_FILE"
AUTH_PAGE_HTML=$(perform_curl "$LOGIN_URL" 2>&1)

CHALLENGE=$(echo "$AUTH_PAGE_HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$AUTH_PAGE_HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$AUTH_PAGE_HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
MAC=$(echo "$AUTH_PAGE_HTML" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$AUTH_PAGE_HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

# Step 3: Initial Auth
echo "Step 3: Submitting login credentials..." | tee -a "$LOG_FILE"
FORM_ACTION=$(echo "$LOGIN_URL" | cut -d'?' -f1)
POST_DATA="username=&password=&button=Login&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&nasid=$NASID"
POST_RESPONSE=$(perform_curl -X POST -d "$POST_DATA" "$FORM_ACTION" 2>&1)

# Step 4: Handle secondary redirect/acceptance page
echo "Step 4: Handling post-login redirection..." | tee -a "$LOG_FILE"
PRELOGIN_LINK=$(echo "$POST_RESPONSE" | sed -n 's/.*href="\([^"]*\/prelogin\)".*/\1/p' | head -n 1)
if [ -n "$PRELOGIN_LINK" ]; then
    echo "Found prelogin trigger: $PRELOGIN_LINK" | tee -a "$LOG_FILE"
    perform_curl "$PRELOGIN_LINK" > /dev/null 2>&1
fi

# Verification
echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: No connectivity (Code: $CHECK_CODE)"
    exit 1
fi
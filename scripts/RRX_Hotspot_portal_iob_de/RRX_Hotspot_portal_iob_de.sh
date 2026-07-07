#!/bin/bash
# SCRIPT_VERSION="1.0.0"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Login Process..." | tee -a "$LOG_FILE"

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

echo "Step 1: Capturing Initial Redirect..." | tee -a "$LOG_FILE"
INITIAL_REDIRECT_RESPONSE=$(perform_curl "http://neverssl.com" 2>&1)
REDIRECT_URL=$(echo "$INITIAL_REDIRECT_RESPONSE" | grep "Location:" | sed 's/Location: //g' | sed 's/\r//g' | tail -n 1)

if [ -z "$REDIRECT_URL" ]; then
    echo "ERROR: Initial redirect URL not found. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

LOGIN_URL=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\([^&]*\).*/\1/p' | sed 's/%3a/:/g;s/%2f/\//g;s/%26/\&/g;s/%3d/=/g')

echo "Step 2: Accessing Hotsplots login page..." | tee -a "$LOG_FILE"
HOTSPOTS_LOGIN_PAGE_HTML=$(perform_curl "$LOGIN_URL" 2>&1)
FORM_ACTION=$(echo "$LOGIN_URL" | cut -d'?' -f1)

CHALLENGE=$(echo "$HOTSPOTS_LOGIN_PAGE_HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HOTSPOTS_LOGIN_PAGE_HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HOTSPOTS_LOGIN_PAGE_HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
MAC=$(echo "$HOTSPOTS_LOGIN_PAGE_HTML" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$HOTSPOTS_LOGIN_PAGE_HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

echo "Step 3: Submitting initial credentials..." | tee -a "$LOG_FILE"
POST_DATA="username=&password=&button=Login&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&nasid=$NASID"
POST_LOGIN_HTML=$(perform_curl -X POST -d "$POST_DATA" "$FORM_ACTION" 2>&1)

echo "Step 4: Handling secondary landing page..." | tee -a "$LOG_FILE"
# The provided HTML indicates a 'NeverSSL' redirection loop or a portal transition.
# We check for the 'Online gehen' button which is standard for these portals.
PRELOGIN_URL=$(echo "$POST_LOGIN_HTML" | sed -n 's/.*<a href="\([^"]*\)" class="btn btn-primary btn-lg">Online gehen<\/a>.*/\1/p')

if [ -n "$PRELOGIN_URL" ]; then
    echo "Found activation link, clicking..." | tee -a "$LOG_FILE"
    perform_curl "$PRELOGIN_URL" > /dev/null 2>&1
fi

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{\\http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: No connectivity (Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
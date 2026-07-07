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

echo "Step 1: Accessing initial redirect to capture Hotsplots parameters..." | tee -a "$LOG_FILE"
RESPONSE=$(perform_curl "http://neverssl.com" 2>&1)
REDIRECT_URL=$(echo "$RESPONSE" | grep "Location:" | sed 's/Location: //g' | sed 's/\r//g' | tail -n 1)

LOGIN_URL=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\([^&]*\).*/\1/p' | sed 's/%3a/:/g;s/%2f/\//g;s/%26/\&/g;s/%3d/=/g')

echo "Step 2: Accessing Hotsplots login page..." | tee -a "$LOG_FILE"
HTML=$(perform_curl "$LOGIN_URL" 2>&1)

echo "Extracting form parameters from Hotsplots..." | tee -a "$LOG_FILE"
FORM_ACTION=$(echo "$LOGIN_URL" | cut -d'?' -f1)
CHALLENGE=$(echo "$HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
MAC=$(echo "$HTML" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

echo "Step 3: Submitting login form..." | tee -a "$LOG_FILE"
POST_DATA="username=&password=&button=Login&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&nasid=$NASID"

AUTH_RESPONSE=$(perform_curl -X POST -d "$POST_DATA" "$FORM_ACTION" 2>&1)

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: No Internet connectivity (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
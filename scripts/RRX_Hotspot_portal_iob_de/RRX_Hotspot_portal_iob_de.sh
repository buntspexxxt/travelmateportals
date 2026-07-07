#!/bin/bash
# SCRIPT_VERSION="1.2.0"
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

echo "Step 1: Extracting Hotsplots parameters from redirection..." | tee -a "$LOG_FILE"
HEADERS=$(curl -k -v -I -A "$USER_AGENT" "http://neverssl.com" 2>&1)
REDIRECT_URL=$(echo "$HEADERS" | sed -n 's/^[Ll]ocation: \(.*\)/\1/p' | sed 's/\r//g' | head -n 1)

# Extract base login URL and params
HOTSPLOTS_LOGIN_URL=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\(.*\)/\1/p' | sed 's/%3a/:/g;s/%2f/\//g;s/%26/\&/g;s/%3d/=/g')

CHALLENGE=$(echo "$HOTSPLOTS_LOGIN_URL" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
UAMIP=$(echo "$HOTSPLOTS_LOGIN_URL" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$HOTSPLOTS_LOGIN_URL" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
MAC=$(echo "$HOTSPLOTS_LOGIN_URL" | sed -n 's/.*mac=\([^&]*\).*/\1/p')
NASID=$(echo "$HOTSPLOTS_LOGIN_URL" | sed -n 's/.*nasid=\([^&]*\).*/\1/p')

echo "Step 2: Visiting prelogin page to initialize session..." | tee -a "$LOG_FILE"
perform_curl "http://192.168.44.1/prelogin"

echo "Step 3: Submitting Hotsplots Auth (Agreeing to terms)..." | tee -a "$LOG_FILE"
POST_DATA="username=&password=&button=Login&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&nasid=$NASID"
FORM_ACTION=$(echo "$HOTSPLOTS_LOGIN_URL" | cut -d'?' -f1)
perform_curl -X POST -d "$POST_DATA" "$FORM_ACTION"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
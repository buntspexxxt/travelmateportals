#!/bin/bash
# SCRIPT_VERSION="1.1.0"
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

echo "Step 1: Detecting redirect..." | tee -a "$LOG_FILE"
REDIRECT_INFO=$(curl -k -v -I -A "$USER_AGENT" "http://neverssl.com" 2>&1)
LOGIN_URL_ENCODED=$(echo "$REDIRECT_INFO" | sed -n 's/.*loginurl=\([^ ]*\).*/\1/p' | sed 's/\r//g')

# Handle URL decoding for the login parameter
LOGIN_URL=$(echo -e "${LOGIN_URL_ENCODED//%/\\x}")

echo "Step 2: Accessing the Hotsplots auth page..." | tee -a "$LOG_FILE"
AUTH_HTML=$(perform_curl "$LOGIN_URL")

echo "Step 3: Extracting CoovaChilli parameters..." | tee -a "$LOG_FILE"
CHALLENGE=$(echo "$AUTH_HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$AUTH_HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$AUTH_HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
MAC=$(echo "$AUTH_HTML" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$AUTH_HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

# If variables are missing, fallback to parsing them from the initial URL
[ -z "$CHALLENGE" ] && CHALLENGE=$(echo "$LOGIN_URL" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
[ -z "$UAMIP" ] && UAMIP=$(echo "$LOGIN_URL" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')

echo "Step 4: Submitting auth form..." | tee -a "$LOG_FILE"
# The portal requires the 'button=Login' and empty user/pass for guest access
POST_DATA="username=&password=&button=Login&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&nasid=$NASID"
perform_curl -X POST -d "$POST_DATA" "$LOGIN_URL"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/bash
# SCRIPT_VERSION="1.3.0"
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

echo "Step 1: Extracting auth redirect URL from portal.iob.de..." | tee -a "$LOG_FILE"
INITIAL_PAGE=$(perform_curl -s "http://portal.iob.de/")
# The logs showed the redirect URL is passed via a query parameter 'loginurl' in the initial redirect
REDIRECT_URL=$(curl -I -k -s -A "$USER_AGENT" "http://neverssl.com" | grep -i "Location:" | sed 's/Location: //g' | sed 's/\r//g')

# Extract the Hotsplots URL from the nested loginurl parameter if present
AUTH_TARGET=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\(.*\)/\1/p' | sed 's/%3a/:/g' | sed 's/%2f/\//g' | sed 's/%3f/?/g' | sed 's/%26/\&/g' | sed 's/\&userurl=.*//g')

if [ -z "$AUTH_TARGET" ]; then
    echo "Direct extraction failed, trying default Hotsplots auth path..." | tee -a "$LOG_FILE"
    AUTH_TARGET="https://www.hotsplots.de/auth/login.php?res=notyet"
fi

echo "Step 2: Connecting to Hotsplots auth page: $AUTH_TARGET" | tee -a "$LOG_FILE"
AUTH_PAGE=$(perform_curl -s "$AUTH_TARGET")

CHALLENGE=$(echo "$AUTH_PAGE" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$AUTH_PAGE" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$AUTH_PAGE" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
MAC=$(echo "$AUTH_PAGE" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$AUTH_PAGE" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

echo "Step 3: Submitting Hotsplots auth POST data..." | tee -a "$LOG_FILE"
# Hotsplots portals typically require these fields to proceed
POST_DATA="username=&password=&button=Login&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&nasid=$NASID"
perform_curl -X POST -d "$POST_DATA" "$AUTH_TARGET"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
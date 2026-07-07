#!/bin/bash
# SCRIPT_VERSION="1.2.0"
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)

echo "Starting Hotspot login process..." | tee -a "$LOG_FILE"
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 2
done

echo "Fetching landing page to extract dynamic parameters..." | tee -a "$LOG_FILE"
# Get initial landing page. The portal will redirect us to the login page.
curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" "http://neverssl.com" -o "$HTML_FILE"
HTML=$(cat "$HTML_FILE")

echo "Extracting hidden form inputs..." | tee -a "$LOG_FILE"
CHALLENGE=$(echo "$HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p' | sed 's/\r//g')
UAMIP=$(echo "$HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p' | sed 's/\r//g')
UAMPORT=$(echo "$HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p' | sed 's/\r//g')
NASID=$(echo "$HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p' | sed 's/\r//g')
USERURL=$(echo "$HTML" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p' | sed 's/\r//g')

if [ -z "$CHALLENGE" ]; then
    echo "Error: Could not extract form parameters. The portal might already be authenticated." | tee -a "$LOG_FILE"
else
    echo "Submitting Terms Acceptance POST request..." | tee -a "$LOG_FILE"
    # We send haveTerms=1 and termsOK=on to accept AGB as per form definition.
    POST_DATA="haveTerms=1&termsOK=on&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&userurl=$USERURL&myLogin=agb&ll=de&nasid=$NASID&custom=1&button=kostenlos+einloggen"
    RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" "https://www.hotsplots.de/auth/login.php" 2>&1)
    echo "Login Request complete." | tee -a "$LOG_FILE"
fi

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
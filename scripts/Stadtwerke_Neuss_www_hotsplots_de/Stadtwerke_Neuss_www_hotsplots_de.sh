#!/bin/bash
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE}" "${HTML_FILE}"' EXIT
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Fetching Peplink session state..." | tee -a "$LOG_FILE"
# Initial request to capture session and redirect parameters
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -m 15 -w "%{url_effective}" -o "$HTML_FILE" "http://neverssl.com")

echo "Parsing session parameters from HTML..." | tee -a "$LOG_FILE"
HTML=$(cat "$HTML_FILE")
SN=$(echo "$HTML" | sed -n 's/.*sn: "\([^"]*\)".*/\1/p' | head -n 1)
SSID=$(echo "$HTML" | sed -n 's/.*ssid: "\([^"]*\)".*/\1/p' | head -n 1)
CHECKSUM=$(echo "$HTML" | sed -n 's/.*checksum: "\([^"]*\)".*/\1/p' | head -n 1)
CP_ID=$(echo "$HTML" | sed -n 's/.*cp_id: "\([^"]*\)".*/\1/p' | head -n 1)

# Perform session resume check
RESUME_URL="https://guest7.ic.peplink.com/cp/session/resume?client_mac=4E:6D:BA:0C:8F:84&sn=$SN&ssid=$SSID&time=$(date +%s)&cp_id=$CP_ID&checksum=$CHECKSUM"
echo "Requesting resume login..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 "$RESUME_URL")
echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

# Submit the final login command
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?command=login&sn=$SN&ssid=$SSID&cp_id=$CP_ID&checksum=$CHECKSUM"
echo "Executing final login..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 "$LOGIN_URL"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 15 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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

echo "Fetching captive portal landing page..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o "$HTML_OUT" "http://neverssl.com"

echo "Extracting API details from page..." | tee -a "$LOG_FILE"
# Extract parameters used by Peplink JS to perform the session resume
CLIENT_MAC=$(sed -n 's/.*client_mac: "\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1)
SN=$(sed -n 's/.*sn: "\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1)
SSID=$(sed -n 's/.*ssid: "\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1)
TIME=$(sed -n 's/.*time:"\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1)
CP_ID=$(sed -n 's/.*cp_id: "\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1)
CHECKSUM=$(sed -n 's/.*checksum:"\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1)

if [ -z "$CLIENT_MAC" ]; then
    echo "ERROR: Failed to extract session parameters." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Attempting session resume via API..." | tee -a "$LOG_FILE"
API_RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "client_mac=$CLIENT_MAC" -d "sn=$SN" -d "ssid=$SSID" -d "time=$TIME" -d "cp_id=$CP_ID" -d "checksum=$CHECKSUM" -d "_=$(date +%s%3N)" "https://guest7.ic.peplink.com/cp/session/resume")

echo "Checking if secondary interaction is required..." | tee -a "$LOG_FILE"
# If response contains needs_sign_in or similar logic, we perform the follow-up request
curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "client_mac=$CLIENT_MAC" -d "sn=$SN" -d "ssid=$SSID" -d "time=$TIME" -d "cp_id=$CP_ID" -d "checksum=$CHECKSUM" -d "command=login" "https://guest7.ic.peplink.com/cp/login"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1
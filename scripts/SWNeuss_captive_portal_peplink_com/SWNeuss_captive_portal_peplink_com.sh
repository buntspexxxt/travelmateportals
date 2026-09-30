#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/120.0.0.0"

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
    i=$((i + 1))
done

echo "Fetching initial portal page to get session variables..." | tee -a "$LOG_FILE"
HTML_OUT=$(curl -k -A "$USER_AGENT" -L -c "$COOKIE_FILE" "http://neverssl.com")

echo "Extracting session parameters from HTML..." | tee -a "$LOG_FILE"
CLIENT_MAC=$(echo "$HTML_OUT" | sed -n 's/.*client_mac: "\([^"]*\)".*/\1/p' | head -n 1)
SN=$(echo "$HTML_OUT" | sed -n 's/.*sn: "\([^"]*\)".*/\1/p' | head -n 1)
SSID=$(echo "$HTML_OUT" | sed -n 's/.*ssid: "\([^"]*\)".*/\1/p' | head -n 1)
TIME=$(echo "$HTML_OUT" | sed -n 's/.*time:"\([^"]*\)".*/\1/p' | head -n 1)
CP_ID=$(echo "$HTML_OUT" | sed -n 's/.*cp_id: "\([^"]*\)".*/\1/p' | head -n 1)
CHECKSUM=$(echo "$HTML_OUT" | sed -n 's/.*checksum:"\([^"]*\)".*/\1/p' | head -n 1)

if [ -z "$CLIENT_MAC" ]; then
    echo "Failed to extract parameters. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Attempting to resume session..." | tee -a "$LOG_FILE"
RESUME_DATA=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -G \
  --data-urlencode "client_mac=$CLIENT_MAC" \
  --data-urlencode "sn=$SN" \
  --data-urlencode "ssid=$SSID" \
  --data-urlencode "time=$TIME" \
  --data-urlencode "cp_id=$CP_ID" \
  --data-urlencode "checksum=$CHECKSUM" \
  "https://guest7.ic.peplink.com/cp/session/resume")

echo "API Response: $RESUME_DATA" | tee -a "$LOG_FILE"

echo "Triggering login command..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -G \
  --data-urlencode "resume=true" \
  --data-urlencode "command=login" \
  --data-urlencode "client_mac=$CLIENT_MAC" \
  --data-urlencode "sn=$SN" \
  --data-urlencode "ssid=$SSID" \
  --data-urlencode "cp_id=$CP_ID" \
  --data-urlencode "checksum=$CHECKSUM" \
  "https://guest7.ic.peplink.com/cp/login"

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
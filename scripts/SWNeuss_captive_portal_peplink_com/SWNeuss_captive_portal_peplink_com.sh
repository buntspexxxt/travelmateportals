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

echo "Starting Peplink Portal Auth..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_OUT" -A "$USER_AGENT" "http://neverssl.com")

# Extract parameters for API calls
SN=$(grep -oE 'sn: "[^"]+"' "$HTML_OUT" | cut -d'"' -f2)
SSID=$(grep -oE 'ssid: "[^"]+"' "$HTML_OUT" | cut -d'"' -f2)
TIME=$(grep -oE 'time:"[^"]+"' "$HTML_OUT" | cut -d'"' -f2)
CP_ID=$(grep -oE 'cp_id: "[^"]+"' "$HTML_OUT" | cut -d'"' -f2)
CHECKSUM=$(grep -oE 'checksum:"[^"]+"' "$HTML_OUT" | cut -d'"' -f2)
CLIENT_MAC=$(grep -oE 'client_mac: "[^"]+"' "$HTML_OUT" | cut -d'"' -f2)

# Step 1: Session Resume
echo "Attempting session resume..." | tee -a "$LOG_FILE"
RESUME_RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 -G "https://guest7.ic.peplink.com/cp/session/resume" \
    --data-urlencode "client_mac=$CLIENT_MAC" \
    --data-urlencode "sn=$SN" \
    --data-urlencode "ssid=$SSID" \
    --data-urlencode "time=$TIME" \
    --data-urlencode "cp_id=$CP_ID" \
    --data-urlencode "checksum=$CHECKSUM" \
    --data-urlencode "_=$(date +%s)")

echo "Resume Response: $RESUME_RESPONSE" | tee -a "$LOG_FILE"

# Step 2: Login Call
echo "Executing login command..." | tee -a "$LOG_FILE"
LOGIN_URL="https://guest7.ic.peplink.com/cp/login"
curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 -G "$LOGIN_URL" \
    --data-urlencode "command=login" \
    --data-urlencode "sn=$SN" \
    --data-urlencode "ssid=$SSID" \
    --data-urlencode "cp_id=$CP_ID" \
    --data-urlencode "checksum=$CHECKSUM" \
    --data-urlencode "client_mac=$CLIENT_MAC" \
    --data-urlencode "time=$TIME" \
    --data-urlencode "resume=true" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        rm -f "$HTML_OUT"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done
rm -f "$HTML_OUT"
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1
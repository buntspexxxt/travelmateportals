#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/wifi_login.log"
COOKIE_FILE="/tmp/c.txt"
HTML_OUT="/tmp/portal_landing.html"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Fetching landing page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "http://neverssl.com" | tr -d '\015')
BASE_HOST=$(echo "$EFFECTIVE_URL" | sed -n 's/\(https*:\/\/[^\/]*\).*/\1/p')

echo "Initializing portal..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -o /dev/null -m 15 "$EFFECTIVE_URL"

# API init to get state
API_INIT=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" "$BASE_HOST/portal_api.php" -m 15)
echo "API Init: $API_INIT" | tee -a "$LOG_FILE"

# Attempt one-click subscription as per Ucopia standard
echo "Subscribing as guest..." | tee -a "$LOG_FILE"
SUB_RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    --data-urlencode "action=subscribe" \
    --data-urlencode "type=one" \
    --data-urlencode "connect_policy_accept=1" \
    --data-urlencode "private_policy_accept=1" \
    "$BASE_HOST/portal_api.php" -m 15)
echo "Response: $SUB_RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying Internet connectivity..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Connected!" | tee -a "$LOG_FILE"
        exit 0
    fi
    sleep 4
    i=$((i + 1))
done
echo "ERROR: Connection failed." | tee -a "$LOG_FILE"
exit 1
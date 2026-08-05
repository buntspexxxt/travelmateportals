#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/wifi_login.log"
COOKIE_FILE="/tmp/c.txt"
HTML_OUT="/tmp/portal_landing.html"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT

echo "Starting Ucopia portal automation..." | tee -a "$LOG_FILE"

echo "Waiting for network readiness..." | tee -a "$LOG_FILE"
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

echo "Fetching landing page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "http://neverssl.com" | tr -d '\015')
BASE_HOST=$(echo "$EFFECTIVE_URL" | sed -n 's/\(https*:\/\/[^\/]*\).*/\1/p')

if [ -z "$BASE_HOST" ]; then BASE_HOST="https://wifiaccess.co"; fi

# API Init
echo "Initializing API..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" "$BASE_HOST/portal_api.php" -m 15 > /dev/null

# Perform 1-click subscription
echo "Attempting one-click subscription..." | tee -a "$LOG_FILE"
SUB_RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    --data-urlencode "action=subscribe" \
    --data-urlencode "type=one" \
    --data-urlencode "connect-policy-accept=1" \
    "$BASE_HOST/portal_api.php" -m 15)
echo "Sub Response: $SUB_RESPONSE" | tee -a "$LOG_FILE"

# Authenticate
echo "Authenticating..." | tee -a "$LOG_FILE"
AUTH_RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    --data-urlencode "action=authenticate" \
    --data-urlencode "policy-accept=1" \
    "$BASE_HOST/portal_api.php" -m 15)
echo "Auth Response: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

# Connectivity verification
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
echo "ERROR: Portal request completed but no Internet connectivity established." | tee -a "$LOG_FILE"
exit 1
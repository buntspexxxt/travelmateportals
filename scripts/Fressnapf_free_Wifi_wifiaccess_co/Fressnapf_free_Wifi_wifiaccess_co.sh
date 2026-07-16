#!/bin/sh
# SCRIPT_VERSION="1.1.0"

LOG_FILE="/tmp/wifi_login.log"
COOKIE_FILE="/tmp/c.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
HTML_OUT="/tmp/portal_landing.html"

trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT

echo "Starting Ucopia portal automation..." | tee -a "$LOG_FILE"

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

echo "Detecting captive portal redirection..." | tee -a "$LOG_FILE"
# Follow redirect to get the effective landing URL
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "http://neverssl.com")
echo "Effective portal URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extract the base scheme and host (e.g. https://wifiaccess.co)
BASE_HOST=$(echo "$EFFECTIVE_URL" | sed -n 's/\(https*:\/\/[^\/]*\).*/\1/p')
if [ -z "$BASE_HOST" ]; then
    echo "ERROR: Could not resolve base host from effective URL. Defaulting to https://wifiaccess.co" | tee -a "$LOG_FILE"
    BASE_HOST="https://wifiaccess.co"
fi

echo "Base host determined: $BASE_HOST" | tee -a "$LOG_FILE"

# Clear old cookies
rm -f "$COOKIE_FILE"

echo "Fetching landing page to establish cookies..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -o /dev/null -m 15 "$EFFECTIVE_URL" -v 2>&1 | tee -a "$LOG_FILE"

echo "Initializing API connection..." | tee -a "$LOG_FILE"
API_INIT=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -d "action=init" \
    "$BASE_HOST/portal_api.php" -m 15 -v 2>&1)
echo "API Init Response: $API_INIT" | tee -a "$LOG_FILE"

echo "Attempting connection using action=authenticate..." | tee -a "$LOG_FILE"
AUTH_RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    --data-urlencode "action=authenticate" \
    --data-urlencode "login=" \
    --data-urlencode "password=" \
    --data-urlencode "policy_accept=1" \
    --data-urlencode "from_ajax=true" \
    "$BASE_HOST/portal_api.php" -m 15 -v 2>&1)
echo "Auth Response: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

# In Ucopia, if direct authentication with empty strings is not sufficient,
# guest/free internet is often registered as a 'one' click subscription.
# Let's perform a one-click guest subscription request.
echo "Attempting backup guest subscription (type=one)..." | tee -a "$LOG_FILE"
SUB_RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    --data-urlencode "action=subscribe" \
    --data-urlencode "type=one" \
    --data-urlencode "connect_policy_accept=1" \
    --data-urlencode "private_policy_accept=1" \
    "$BASE_HOST/portal_api.php" -m 15 -v 2>&1)
echo "Subscription Response: $SUB_RESPONSE" | tee -a "$LOG_FILE"

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
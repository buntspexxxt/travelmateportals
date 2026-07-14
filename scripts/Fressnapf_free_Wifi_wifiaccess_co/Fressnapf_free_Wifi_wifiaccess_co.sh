#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/wifi_login.log"
COOKIE_FILE="/tmp/c.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

trap 'rm -f "$COOKIE_FILE"' EXIT

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

echo "Fetching landing page to obtain session cookies..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o /dev/null -m 15 "https://wifiaccess.co/103/portal/" -v >> "$LOG_FILE" 2>&1

echo "Initializing API..." | tee -a "$LOG_FILE"
API_INIT=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" "https://wifiaccess.co/portal_api.php" -m 15 -v 2>&1)
echo "API Init Response: $API_INIT" | tee -a "$LOG_FILE"

echo "Attempting connection with policy acceptance..." | tee -a "$LOG_FILE"
AUTH_RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" --data-urlencode "action=authenticate" --data-urlencode "login=" --data-urlencode "password=" --data-urlencode "policy_accept=1" "https://wifiaccess.co/portal_api.php" -m 15 -v 2>&1)
echo "Auth Response: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

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
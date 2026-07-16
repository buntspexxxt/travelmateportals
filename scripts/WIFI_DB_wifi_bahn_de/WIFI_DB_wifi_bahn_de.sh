#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Trap for cleanup
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

LOG_FILE="/tmp/portal_login.log"
echo "Starting portal login sequence for WIFI_DB_wifi_bahn_de" | tee -a "$LOG_FILE"

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

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
TARGET_DOMAIN="wifi.bahn.de"
CHECK_URL="https://${TARGET_DOMAIN}/en/"

echo "Fetching initial session and CSRF token from ${TARGET_DOMAIN}..." | tee -a "$LOG_FILE"
curl -k -v -A "$UA" -c "$COOKIE_FILE" -o /dev/null -m 15 "$CHECK_URL" 2>>"$LOG_FILE"

# Extract CSRF token from cookies
CSRF_TOKEN=$(grep 'csrf' "$COOKIE_FILE" | tail -n 1 | awk '{print $7}')

if [ -z "$CSRF_TOKEN" ]; then
    echo "Primary domain failed. Trying login.wifionice.de..." | tee -a "$LOG_FILE"
    TARGET_DOMAIN="login.wifionice.de"
    CHECK_URL="https://${TARGET_DOMAIN}/en/"
    curl -k -v -A "$UA" -c "$COOKIE_FILE" -o /dev/null -m 15 "$CHECK_URL" 2>>"$LOG_FILE"
    CSRF_TOKEN=$(grep 'csrf' "$COOKIE_FILE" | tail -n 1 | awk '{print $7}')
fi

if [ -z "$CSRF_TOKEN" ]; then
    echo "Failed to extract CSRF token!" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting login POST request..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -A "$UA" -b "$COOKIE_FILE" -H "Cookie: csrf=$CSRF_TOKEN" --data-urlencode "login=true" --data-urlencode "CSRFToken=$CSRF_TOKEN" -m 15 "https://${TARGET_DOMAIN}/en/")

echo "HTTP Response from login request: $RESPONSE_CODE" | tee -a "$LOG_FILE"

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
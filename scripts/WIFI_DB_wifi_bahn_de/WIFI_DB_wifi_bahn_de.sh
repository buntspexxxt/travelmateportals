#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Starting portal login sequence for WIFI_DB_wifi_bahn_de" | tee -a "$LOG_FILE"

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

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
DOMAINS="wifi.bahn.de login.wifionice.de"

for DOMAIN in $DOMAINS; do
    echo "Attempting to fetch session from $DOMAIN..." | tee -a "$LOG_FILE"
    curl -k -v -A "$UA" -c "$COOKIE_FILE" -o /dev/null -m 10 "https://$DOMAIN/en/" >>"$LOG_FILE" 2>&1
    CSRF_TOKEN=$(grep -i 'csrf' "$COOKIE_FILE" | tail -n 1 | awk '{print $7}' | tr -d '\015')
    
    if [ -n "$CSRF_TOKEN" ]; then
        echo "CSRF Token found: $CSRF_TOKEN" | tee -a "$LOG_FILE"
        echo "Submitting login..." | tee -a "$LOG_FILE"
        RESPONSE=$(curl -k -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
            --data-urlencode "login=true" \
            --data-urlencode "CSRFToken=$CSRF_TOKEN" \
            -m 15 "https://$DOMAIN/en/" 2>>"$LOG_FILE")
        break
    fi
done

if [ -z "$CSRF_TOKEN" ]; then
    echo "ERROR: Failed to extract CSRF token from any domain." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (Code: $CHECK_CODE)." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established." | tee -a "$LOG_FILE"
exit 1
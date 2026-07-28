#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

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

# Note: The error 'unsafe legacy renegotiation disabled' in previous logs suggests a need for --insecure 
# and potentially dealing with old SSL handshake versions, curl -k covers this.
echo "Fetching initial page to extract CSRF token..." | tee -a "$LOG_FILE"
curl -k -v -A "$UA" -c "$COOKIE_FILE" -o /tmp/portal_html -m 15 "https://$TARGET_DOMAIN/en/" >>"$LOG_FILE" 2>&1

CSRF_TOKEN=$(grep -o 'name="CSRFToken" value="[^"]*"' /tmp/portal_html | sed 's/.*value="\([^"]*\)".*/\1/' | tr -d '\015')

if [ -z "$CSRF_TOKEN" ]; then
    # Fallback attempt via cookie grep if input field extraction fails
    CSRF_TOKEN=$(grep -i 'csrf' "$COOKIE_FILE" | tail -n 1 | awk '{print $7}' | tr -d '\015')
fi

if [ -z "$CSRF_TOKEN" ]; then
    echo "ERROR: Failed to extract CSRF token." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting login POST request..." | tee -a "$LOG_FILE"
# Using data-urlencode to ensure clean payload transmission
curl -k -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    --data-urlencode "login=true" \
    --data-urlencode "CSRFToken=$CSRF_TOKEN" \
    -m 15 "https://$TARGET_DOMAIN/en/" >>"$LOG_FILE" 2>&1

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
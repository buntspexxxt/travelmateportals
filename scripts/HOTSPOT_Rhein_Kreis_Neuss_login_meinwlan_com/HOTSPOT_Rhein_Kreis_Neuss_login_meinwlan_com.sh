#!/bin/sh
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
LOG_FILE="/tmp/portal_log.txt"
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

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_OUT" -w "%{url_effective}" -m 15 "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Extracting MAC addresses from HTML..." | tee -a "$LOG_FILE"
# The portal provides logic: btoa("user_mac=...&mac=...")
# We will simulate the same request structure
USER_MAC=$(cat /sys/class/net/$(ip route | grep default | awk '{print $5}')/address | tr '[:lower:]' '[:upper:]')
# Since we cannot easily get the AP MAC from here, we reuse the pattern found in the HTML logic
MAC_DATA="user_mac=$USER_MAC&mac=$USER_MAC"
RES_VAL=$(echo -n "$MAC_DATA" | openssl base64 | tr -d '
')

echo "Submitting portal login via GET to https://go.meinwlan.com..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" -m 15 -G "https://go.meinwlan.com" \
  --data-urlencode "res=$RES_VAL" \
  --data-urlencode "auth=https://login.meinwlan.com/login")

echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

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
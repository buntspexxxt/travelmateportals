#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_FILE"' EXIT

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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching initial context..." | tee -a "$LOG_FILE"
curl -k -L -A "$USER_AGENT" -o "$HTML_FILE" -c "$COOKIE_FILE" "https://hotspot.t-mobile.net/" >> "$LOG_FILE" 2>&1

echo "Executing free login..." | tee -a "$LOG_FILE"
# The portal uses an Angular SPA; we simulate the REST API endpoint identified in previous attempts.
RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
    --data-urlencode "UserName=" \
    --data-urlencode "Password=" \
    --data-urlencode "FNAME=0" \
    --data-urlencode "button=Login")

echo "Login HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Connected!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected (Code: $CHECK_CODE)." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: No internet established." | tee -a "$LOG_FILE"
exit 1
#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
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

echo "Fetching captive portal redirect..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Navigating to Orange Egypt portal..." | tee -a "$LOG_FILE"
# The portal requires hitting the login.aspx page identified in the meta refresh
curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -o "$HTML_OUT" -m 15 "https://wifi.orange.eg/wifihs/pages/login.aspx"

# NOTE: This portal structure typically requires form submission. 
# Since no explicit form inputs were provided in the prompt, we simulate a standard acceptance POST
echo "Attempting to submit portal login form..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -w "%{http_code}" -o "$HTML_OUT" -m 15 -X POST "https://wifi.orange.eg/wifihs/pages/login.aspx" --data-urlencode "accept=true")
echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

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
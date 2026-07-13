#!/bin/sh
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting H&M Free WiFi authentication" | tee -a "$LOG_FILE"

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

echo "Fetching initial portal redirect..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -v -w "%\{url_effective\}" -A "$USER_AGENT" -o "$HTML_FILE" -m 15 "http://neverssl.com" 2>&1 | grep "Location:" | tail -n 1 | cut -d' ' -f2 | tr -d '\015')

echo "Extracted URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Following dynamic redirection to login page..." | tee -a "$LOG_FILE"
FINAL_URL=$(curl -k -L -w "%\{url_effective\}" -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -o "$HTML_FILE" -m 15 "$EFFECTIVE_URL")

echo "Submitting session acceptance..." | tee -a "$LOG_FILE"
# The portal requires a POST to the /login path with the session state extracted from the URL query params
POST_DATA=$(echo "$FINAL_URL" | sed -n 's/.*\?\(.*\)/\1/p')
RESPONSE_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -d "$POST_DATA" -X POST "$FINAL_URL")

echo "HTTP Response Code: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
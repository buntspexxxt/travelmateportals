#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting Peplink captive portal login..." > "$LOG_FILE"

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

COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Fetching initial redirect to extract parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%\{url_effective\}" -o /dev/null -m 15 "http://neverssl.com" 2>> "$LOG_FILE" | tr -d '\015')

echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Attempting session resume..." | tee -a "$LOG_FILE"
RESUME_RESPONSE=$(curl -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -m 15 "https://guest7.ic.peplink.com/cp/session/resume?$(echo "$EFFECTIVE_URL" | sed -n 's/.*\?\(.*\)/\1/p')" 2>> "$LOG_FILE")

echo "Resume response: $RESUME_RESPONSE" | tee -a "$LOG_FILE"

echo "Submitting login request..." | tee -a "$LOG_FILE"
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?$(echo "$EFFECTIVE_URL" | sed -n 's/.*\?\(.*\)/\1/p')&command=login&resume=true&lang=en"
CURL_OUT=$(curl -k -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -m 15 "$LOGIN_URL" 2>> "$LOG_FILE")

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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
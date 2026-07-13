#!/bin/sh
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Waiting for network..." | tee -a "$LOG_FILE"
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

echo "Fetching landing data..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -m 15 -A "$USER_AGENT" -w "%{url_effective}" -o /dev/null "http://neverssl.com" | tr -d '\015')
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*?\(.*\)/\1/p')
BASE_URL=$(echo "$EFFECTIVE_URL" | cut -d'/' -f1-3)

echo "Resuming session..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -G "$BASE_URL/cp/session/resume" --data-urlencode "client_mac=$(echo "$QUERY_STRING" | sed -n 's/.*client_mac=\([^&]*\).*/\1/p')" --data-urlencode "sn=$(echo "$QUERY_STRING" | sed -n 's/.*sn=\([^&]*\).*/\1/p')" --data-urlencode "ssid=$(echo "$QUERY_STRING" | sed -n 's/.*ssid=\([^&]*\).*/\1/p')" --data-urlencode "time=$(echo "$QUERY_STRING" | sed -n 's/.*time=\([^&]*\).*/\1/p')" --data-urlencode "cp_id=$(echo "$QUERY_STRING" | sed -n 's/.*cp_id=\([^&]*\).*/\1/p')" --data-urlencode "checksum=$(echo "$QUERY_STRING" | sed -n 's/.*checksum=\([^&]*\).*/\1/p')" --data-urlencode "_=$(date +%s)")

echo "Session check response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Submitting final login request..." | tee -a "$LOG_FILE"
# The portal requires a direct call to login endpoint with the same query parameters captured from the initial redirect
LOGIN_URL="$BASE_URL/cp/login?$QUERY_STRING&command=login&resume=true&lang=en&_=$(date +%s)"
curl -k -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LOGIN_URL"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
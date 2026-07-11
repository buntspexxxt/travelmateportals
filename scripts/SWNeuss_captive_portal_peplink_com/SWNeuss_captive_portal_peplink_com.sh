#!/bin/bash
# SCRIPT_VERSION="1.0.0"
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

echo "Fetching redirect URL..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -m 15 -A "$USER_AGENT" -w "%{url_effective}" -o /dev/null "http://neverssl.com" | tr -d '\015')
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*?\(.*\)/\1/p')

echo "Requesting session resume..." | tee -a "$LOG_FILE"
RESUME_RESPONSE=$(curl -k -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -G "https://guest7.ic.peplink.com/cp/session/resume" --data-urlencode "client_mac=$(echo $QUERY_STRING | sed -n 's/.*client_mac=\([^&]*\).*/\1/p')" --data-urlencode "sn=$(echo $QUERY_STRING | sed -n 's/.*sn=\([^&]*\).*/\1/p')" --data-urlencode "ssid=$(echo $QUERY_STRING | sed -n 's/.*ssid=\([^&]*\).*/\1/p')" --data-urlencode "time=$(echo $QUERY_STRING | sed -n 's/.*time=\([^&]*\).*/\1/p')" --data-urlencode "cp_id=$(echo $QUERY_STRING | sed -n 's/.*cp_id=\([^&]*\).*/\1/p')" --data-urlencode "checksum=$(echo $QUERY_STRING | sed -n 's/.*checksum=\([^&]*\).*/\1/p')" --data-urlencode "_=$(date +%s)")

echo "Response: $RESUME_RESPONSE" | tee -a "$LOG_FILE"

echo "Submitting login request..." | tee -a "$LOG_FILE"
curl -k -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -G "https://guest7.ic.peplink.com/cp/login" --data-urlencode "$QUERY_STRING" --data-urlencode "command=login" --data-urlencode "resume=true" --data-urlencode "lang=en" --data-urlencode "_= $(date +%s)"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 10 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Connectivity check failed (Code: $CHECK_CODE)"
    exit 1
fi
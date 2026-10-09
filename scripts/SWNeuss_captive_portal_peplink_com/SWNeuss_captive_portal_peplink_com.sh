#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/120.0.0.0"

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

echo "Fetching initial redirect to identify parameters..." | tee -a "$LOG_FILE"
# Extract parameters directly from the redirect landing page
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -w "%\{url_effective\}" -o /dev/null "http://neverssl.com")
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*\?\(.*\)/\1/p')

echo "Extracted query string: $QUERY_STRING" | tee -a "$LOG_FILE"

echo "Performing session resume call..." | tee -a "$LOG_FILE"
RESUME_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -G --data-urlencode "$_=$(date +%s000)" --data-urlencode "client_mac=$(echo "$QUERY_STRING" | sed -n 's/.*client_mac=\([^&]*\).*/\1/p')" --data-urlencode "sn=$(echo "$QUERY_STRING" | sed -n 's/.*sn=\([^&]*\).*/\1/p')" --data-urlencode "ssid=$(echo "$QUERY_STRING" | sed -n 's/.*ssid=\([^&]*\).*/\1/p')" --data-urlencode "time=$(echo "$QUERY_STRING" | sed -n 's/.*time=\([^&]*\).*/\1/p')" --data-urlencode "cp_id=$(echo "$QUERY_STRING" | sed -n 's/.*cp_id=\([^&]*\).*/\1/p')" --data-urlencode "checksum=$(echo "$QUERY_STRING" | sed -n 's/.*checksum=\([^&]*\).*/\1/p')" "https://guest7.ic.peplink.com/cp/session/resume")

echo "API Response: $RESUME_RESPONSE" | tee -a "$LOG_FILE"

echo "Submitting final login request..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -G --data-urlencode "resume=true" --data-urlencode "command=login" --data-urlencode "sn=$(echo "$QUERY_STRING" | sed -n 's/.*sn=\([^&]*\).*/\1/p')" --data-urlencode "ssid=$(echo "$QUERY_STRING" | sed -n 's/.*ssid=\([^&]*\).*/\1/p')" --data-urlencode "client_mac=$(echo "$QUERY_STRING" | sed -n 's/.*client_mac=\([^&]*\).*/\1/p')" --data-urlencode "cp_id=$(echo "$QUERY_STRING" | sed -n 's/.*cp_id=\([^&]*\).*/\1/p')" --data-urlencode "checksum=$(echo "$QUERY_STRING" | sed -n 's/.*checksum=\([^&]*\).*/\1/p')" "https://guest7.ic.peplink.com/cp/login"

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

echo "ERROR: Portal request completed but no Internet connectivity established." | tee -a "$LOG_FILE"
exit 1
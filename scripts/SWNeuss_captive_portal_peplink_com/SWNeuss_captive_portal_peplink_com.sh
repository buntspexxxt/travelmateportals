#!/bin/bash
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Waiting for network..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then break; fi
    sleep 2
done

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -m 15 -k -A "$USER_AGENT" -o /dev/null -w "%{redirect_url}" "http://neverssl.com" | tr -d '\015')
HOST=$(echo "$REDIRECT_URL" | cut -d/ -f1-3)
QUERY=$(echo "$REDIRECT_URL" | sed -n 's/.*?\(.*\)/\1/p')

echo "Requesting session state..." | tee -a "$LOG_FILE"
SESSION_JSON=$(curl -m 15 -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -G "$HOST/cp/session/resume" --data-urlencode "client_mac=$(echo $QUERY | sed -n 's/.*client_mac=\([^&]*\).*/\1/p')" --data-urlencode "sn=$(echo $QUERY | sed -n 's/.*sn=\([^&]*\).*/\1/p')" --data-urlencode "ssid=$(echo $QUERY | sed -n 's/.*ssid=\([^&]*\).*/\1/p')" --data-urlencode "time=$(echo $QUERY | sed -n 's/.*time=\([^&]*\).*/\1/p')" --data-urlencode "cp_id=$(echo $QUERY | sed -n 's/.*cp_id=\([^&]*\).*/\1/p')" --data-urlencode "checksum=$(echo $QUERY | sed -n 's/.*checksum=\([^&]*\).*/\1/p')" --data-urlencode "_=$(date +%s)")
echo "Response: $SESSION_JSON" | tee -a "$LOG_FILE"

echo "Initiating final login..." | tee -a "$LOG_FILE"
# Based on the provided JS logic, we construct the login URL using existing parameters
LOGIN_URL="$HOST/cp/login?$QUERY"
curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LOGIN_URL"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Connectivity check failed (Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/bash
# SCRIPT_VERSION="1.3.0"
trap 'rm -f "${COOKIE_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)

echo "Starting Peplink Portal Login sequence" | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
done

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -v -A "$USER_AGENT" -o /dev/null -w "%{redirect_url}" "http://connectivitycheck.gstatic.com/generate_204" | sed "s/\r//g")

echo "Resuming session to extract tokens..." | tee -a "$LOG_FILE"
# Extract base URL and query string for session API
BASE_URL="https://guest7.ic.peplink.com"
SESSION_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$BASE_URL/cp/session/resume?client_mac=96:89:AF:5E:34:CA&sn=2939-5050-2D30&ssid=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&time=1783499683&cp_id=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&checksum=ebb2140f8982b07db401024e4688206f06657e3e")
echo "Response: $SESSION_RESPONSE" | tee -a "$LOG_FILE"

echo "Submitting Login Request..." | tee -a "$LOG_FILE"
# Using params extracted from JS logic to perform the login
LOGIN_URL="$BASE_URL/cp/login?resume=true&command=login&lang=en&sn=2939-5050-2D30&ssid=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&ip=10.200.9.212&client_mac=96:89:AF:5E:34:CA&host_ip=192.168.50.1&host_mac=A8:C0:EA:52:C3:00&cp_id=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&checksum=ebb2140f8982b07db401024e4688206f06657e3e&_=$(date +%s)"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LOGIN_URL"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: No internet connectivity (Code: $CHECK_CODE)"
    exit 1
fi
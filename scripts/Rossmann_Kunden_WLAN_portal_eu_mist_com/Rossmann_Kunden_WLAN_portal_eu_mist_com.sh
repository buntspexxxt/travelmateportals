#!/bin/bash
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching portal page to get session parameters..." | tee -a "$LOG_FILE"
HTML=$(curl -m 15 -k -v -A "$USER_AGENT" -c /tmp/portal_cookies.txt -L "http://neverssl.com")

EFFECTIVE_URL=$(curl -m 15 -k -v -A "$USER_AGENT" -b /tmp/portal_cookies.txt -c /tmp/portal_cookies.txt -w "%{url_effective}" -o /dev/null -s "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extract hidden fields dynamically
AP_MAC=$(echo "$HTML" | sed -n 's/.*name="ap_mac" value="\([^"]*\)".*/\1/p' | head -n 1)
CLIENT_MAC=$(echo "$HTML" | sed -n 's/.*name="client_mac" value="\([^"]*\)".*/\1/p' | head -n 1)
WLAN_ID=$(echo "$HTML" | sed -n 's/.*name="wlan_id" value="\([^"]*\)".*/\1/p' | head -n 1)
URL_VAL=$(echo "$HTML" | sed -n 's/.*name="url" value="\([^"]*\)".*/\1/p' | head -n 1)

echo "Submitting form for MAC: $CLIENT_MAC..." | tee -a "$LOG_FILE"

RESPONSE=$(curl -m 15 -k -v -A "$USER_AGENT" -b /tmp/portal_cookies.txt -c /tmp/portal_cookies.txt \
  -d "ap_mac=$AP_MAC" \
  -d "client_mac=$CLIENT_MAC" \
  -d "wlan_id=$WLAN_ID" \
  -d "url=$URL_VAL" \
  -d "tos=true" \
  -d "auth_method=passphrase" \
  "https://portal.eu.mist.com/logon?ap_mac=$AP_MAC&client_mac=$CLIENT_MAC&wlan_id=$WLAN_ID")

echo "HTTP Response Received." | tee -a "$LOG_FILE"

# Final connectivity check
echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
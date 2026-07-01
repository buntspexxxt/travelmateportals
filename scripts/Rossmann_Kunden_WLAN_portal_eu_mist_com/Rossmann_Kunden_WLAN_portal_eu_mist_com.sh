#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching portal page to get session parameters..." | tee -a "$LOG_FILE"
HTML=$(curl -k -v -A "$USER_AGENT" -c /tmp/portal_cookies.txt -L "http://neverssl.com")

EFFECTIVE_URL=$(curl -k -v -A "$USER_AGENT" -b /tmp/portal_cookies.txt -c /tmp/portal_cookies.txt -w "%{url_effective}" -o /dev/null -s "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extract hidden fields dynamically
AP_MAC=$(echo "$HTML" | sed -n 's/.*name="ap_mac" value="\([^"]*\)".*/\1/p' | head -n 1)
CLIENT_MAC=$(echo "$HTML" | sed -n 's/.*name="client_mac" value="\([^"]*\)".*/\1/p' | head -n 1)
WLAN_ID=$(echo "$HTML" | sed -n 's/.*name="wlan_id" value="\([^"]*\)".*/\1/p' | head -n 1)
URL_VAL=$(echo "$HTML" | sed -n 's/.*name="url" value="\([^"]*\)".*/\1/p' | head -n 1)

echo "Submitting form for MAC: $CLIENT_MAC..." | tee -a "$LOG_FILE"

RESPONSE=$(curl -k -v -A "$USER_AGENT" -b /tmp/portal_cookies.txt -c /tmp/portal_cookies.txt \
  -d "ap_mac=$AP_MAC" \
  -d "client_mac=$CLIENT_MAC" \
  -d "wlan_id=$WLAN_ID" \
  -d "url=$URL_VAL" \
  -d "tos=true" \
  -d "auth_method=passphrase" \
  "https://portal.eu.mist.com/logon?ap_mac=$AP_MAC&client_mac=$CLIENT_MAC&wlan_id=$WLAN_ID")

echo "HTTP Response Received." | tee -a "$LOG_FILE"

# Final connectivity check
echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet reached." | tee -a "$LOG_FILE" && exit 0 || exit 1
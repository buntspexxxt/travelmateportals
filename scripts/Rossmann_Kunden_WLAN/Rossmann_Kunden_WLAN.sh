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

echo "Fetching portal page to extract parameters..." | tee -a "$LOG_FILE"
curl -L -v -A "$USER_AGENT" -c /tmp/cookies.txt http://neverssl.com/ > /tmp/portal.html 2>&1

# Extract hidden fields
AP_MAC=$(grep -o 'name="ap_mac" value="[^"]*"' /tmp/portal.html | cut -d'"' -f4 | head -1)
CLIENT_MAC=$(grep -o 'name="client_mac" value="[^"]*"' /tmp/portal.html | cut -d'"' -f4 | head -1)
WLAN_ID=$(grep -o 'name="wlan_id" value="[^"]*"' /tmp/portal.html | cut -d'"' -f4 | head -1)
URL_PARAM=$(grep -o 'name="url" value="[^"]*"' /tmp/portal.html | cut -d'"' -f4 | head -1)

echo "Extracted AP_MAC: $AP_MAC" | tee -a "$LOG_FILE"

echo "Submitting acceptance form..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt \
  --data-urlencode "ap_mac=$AP_MAC" \
  --data-urlencode "client_mac=$CLIENT_MAC" \
  --data-urlencode "wlan_id=$WLAN_ID" \
  --data-urlencode "url=$URL_PARAM" \
  --data-urlencode "tos=true" \
  --data-urlencode "auth_method=passphrase" \
  "https://portal.eu.mist.com/logon?ap_mac=$AP_MAC&client_mac=$CLIENT_MAC&lang=default&url=$URL_PARAM&wlan_id=$WLAN_ID")

echo "Login submission finished." | tee -a "$LOG_FILE"

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 > /dev/null && echo "Connected to internet!" && exit 0 || { echo "Failed to connect."; exit 1; }
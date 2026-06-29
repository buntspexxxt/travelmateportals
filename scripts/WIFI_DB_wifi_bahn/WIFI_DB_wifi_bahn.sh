#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
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

# The logs indicate SSL renegotiation issues with wifi.bahn.de. 
# We bypass this by explicitly allowing insecure renegotiation via openssl config or curl flags if possible.
# Often, train portals require agreeing to TOS on the landing page.
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Accessing landing page to retrieve session cookies..." | tee -a "$LOG_FILE"
# Using --ciphers DEFAULT@SECLEVEL=0 to bypass 'unsafe legacy renegotiation disabled' error
curl -v -k --ciphers 'DEFAULT@SECLEVEL=0' -A "$UA" -c /tmp/cookies.txt https://wifi.bahn.de/ > /dev/null 2>&1

echo "Submitting acceptance form..." | tee -a "$LOG_FILE"
# Based on typical Deutsche Bahn W-Fi portals, usually a POST to /cgi-bin/login or a specific landing URL with a checkbox is required.
# If the portal is indeed wifi.bahn.de, it often requires navigating to their specific start page.
RESPONSE=$(curl -v -k --ciphers 'DEFAULT@SECLEVEL=0' -A "$UA" -b /tmp/cookies.txt -c /tmp/cookies.txt -L -X POST https://wifi.bahn.de/ --data "accept=1")

echo "Response received. Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connectivity restored!" && exit 0 || echo "Login failed." && exit 1
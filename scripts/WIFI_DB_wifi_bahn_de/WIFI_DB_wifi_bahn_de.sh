#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login process for WIFI_DB_wifi_bahn_de" | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# The portal provides 'neverssl.com' which redirects to a random subdomain to bypass HSTS.
# The DB Wi-Fi portal is known to require standard accept-terms interaction via https://wifi.bahn.de/
# Since the logs show 'unsafe legacy renegotiation', we will attempt to use --ciphers 'DEFAULT:@SECLEVEL=0' to bypass restrictive SSL settings.

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Attempting to access portal via non-HTTPS to trigger redirect..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" http://neverssl.com/ -o /dev/null

echo "Attempting to connect to wifi.bahn.de with legacy SSL allowance..." | tee -a "$LOG_FILE"
# We use --ciphers DEFAULT:@SECLEVEL=0 to allow the legacy renegotiation required by some older captive portal gateways
RESPONSE=$(curl -v -A "$USER_AGENT" --ciphers 'DEFAULT:@SECLEVEL=0' -c /tmp/cookies.txt -L "https://wifi.bahn.de/" 2>&1)

echo "Checking if we reached the portal..." | tee -a "$LOG_FILE"
# This portal typically requires a POST request to a specific login endpoint once redirected
# Given the DB portal structure, it usually involves an Accept/Login button POST.
echo "Capturing response headers..." | tee -a "$LOG_FILE"
echo "$RESPONSE" | tee -a "$LOG_FILE"

echo "Finalizing connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet reached." | tee -a "$LOG_FILE" && exit 0 || echo "Failed: Connectivity not established." | tee -a "$LOG_FILE" && exit 1
#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting Peplink Captive Portal authentication..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then break; fi
    sleep 1
done

echo "Initial check for session..." | tee -a "$LOG_FILE"
# Extract parameters from initial redirect or assume standard Peplink session query
# The JS uses a specific API at https://guest7.ic.peplink.com/cp/session/resume
RESPONSE=$(curl -v -A "$USER_AGENT" -G "https://guest7.ic.peplink.com/cp/session/resume" \
    --data-urlencode "client_mac=06:1E:57:73:56:30" \
    --data-urlencode "sn=2939-EF23-E500" \
    --data-urlencode "ssid=~CP_KEY_KoqKCOTKsie-rX87wdb1qA" \
    --data-urlencode "time=1783058563" \
    --data-urlencode "cp_id=~CP_KEY_KoqKCOTKsie-rX87wdb1qA" \
    --data-urlencode "checksum=91a33d2efe089d0d09268d244769492d85e02bba" 2>&1)

echo "Session API Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Sending login command..." | tee -a "$LOG_FILE"
# The JS logic indicates a POST or redirect to /cp/login with the same parameters as the resume call
curl -v -A "$USER_AGENT" -G "https://guest7.ic.peplink.com/cp/login" \
    --data-urlencode "command=login" \
    --data-urlencode "resume=true" \
    --data-urlencode "client_mac=06:1E:57:73:56:30" \
    --data-urlencode "sn=2939-EF23-E500" \
    --data-urlencode "ssid=~CP_KEY_KoqKCOTKsie-rX87wdb1qA" \
    --data-urlencode "time=1783058563" \
    --data-urlencode "cp_id=~CP_KEY_KoqKCOTKsie-rX87wdb1qA" \
    --data-urlencode "checksum=91a33d2efe089d0d09268d244769492d85e02bba" 2>&1 | tee -a "$LOG_FILE"

sleep 5
echo "Connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null 2>&1 && exit 0 || exit 1
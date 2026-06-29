#!/bin/bash

LOG_FILE="/tmp/portal_log.txt"
echo "Starting RRX_Hotspot automation script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Analyzing the portal content..." | tee -a "$LOG_FILE"
# The provided HTML is just 'NeverSSL', a utility page used to trigger redirects.
# It does not contain an actual login form, but instead relies on the browser's 
# reaction to unencrypted traffic to trigger the hotspot's intercept.

echo "The HTML provided appears to be a cache-busting landing page (NeverSSL)." | tee -a "$LOG_FILE"
echo "This portal requires a manual redirect or browser-based interaction to trigger the actual login page." | tee -a "$LOG_FILE"

# Perform connectivity check to see if we are already online
curl -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" http://neverssl.com/ > /dev/null 2>&1
RESPONSE=$?
if [ $RESPONSE -eq 0 ]; then
    echo "Connectivity test successful. Already online." | tee -a "$LOG_FILE"
    exit 0
else
    echo "Connectivity test failed. The portal is active but the login mechanism is not automated in this HTML." | tee -a "$LOG_FILE"
    exit 1
fi
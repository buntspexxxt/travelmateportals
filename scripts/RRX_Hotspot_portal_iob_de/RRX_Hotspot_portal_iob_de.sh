#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting RRX Hotspot Login Process..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# 2. Capture Redirect URL to extract Hotsplots parameters
echo "Fetching initial redirect to extract Hotsplots parameters..." | tee -a "$LOG_FILE"
REDIRECT_OUTPUT=$(curl -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" http://neverssl.com 2>&1)
echo "Raw Curl Output:\
$REDIRECT_OUTPUT" | tee -a "$LOG_FILE"

# Extract the Location header which contains the Hotsplots URL
LOGIN_URL=$(echo "$REDIRECT_OUTPUT" | sed -n 's/.*Location: //p' | tr -d '\\r')
echo "Found Login URL: $LOGIN_URL" | tee -a "$LOG_FILE"

# 3. Perform Login
# The portal logic uses the Hotsplots auth URL extracted above.
echo "Submitting login request to Hotsplots..." | tee -a "$LOG_FILE"
# Hotsplots usually accepts a POST to the login URL with empty credentials for open Wi-Fi
LOGIN_RESPONSE=$(curl -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -d "username=&password=&button=Login" "$LOGIN_URL" 2>&1)

echo "HTTP Response from Login: $LOGIN_RESPONSE" | tee -a "$LOG_FILE"

# 4. Connectivity check
echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access restored." || { echo "Error: Connectivity test failed."; exit 1; }
exit 0
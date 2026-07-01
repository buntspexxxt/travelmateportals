#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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

# 2. Trigger initial redirect to capture Hotsplots parameters
echo "Fetching initial redirect to extract Hotsplots parameters..." | tee -a "$LOG_FILE"
# We fetch the URL that holds the 'loginurl' parameter in its Location header
RESPONSE=$(curl -v -A "$USER_AGENT" http://neverssl.com 2>&1)

# Extract the loginurl parameter (the Hotsplots auth URL)
LOGIN_URL=$(echo "$RESPONSE" | sed -n 's/.*loginurl=\([^ ]*\).*/\1/p' | sed 's/%3a/:/g;s/%2f/\//g;s/%26/\&/g;s/%3d/=/g' | tr -d '\r')

if [ -z "$LOGIN_URL" ]; then
    echo "Failed to extract LOGIN_URL. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Found Hotsplots Auth URL: $LOGIN_URL" | tee -a "$LOG_FILE"

# 3. Perform Prelogin (The RRX specific step)
echo "Accessing prelogin page on the router..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" http://192.168.44.1/prelogin >> "$LOG_FILE" 2>&1

# 4. Perform final auth with Hotsplots
echo "Submitting final login request to Hotsplots..." | tee -a "$LOG_FILE"
# Based on the Hotsplots standard protocol, we POST the required fields
AUTH_RESPONSE=$(curl -v -A "$USER_AGENT" -d "username=&password=&button=Login" "$LOGIN_URL" 2>&1)

echo "Auth Response: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

# 5. Connectivity check
echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access restored." || { echo "Error: Connectivity test failed."; exit 1; }
exit 0
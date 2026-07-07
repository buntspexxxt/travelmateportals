#!/bin/bash
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Login Process..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# 2. Extract redirect parameters
echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -v -A "$USER_AGENT" -o /dev/null -w "%{redirect_url}" http://neverssl.com 2>&1 | sed -n 's/.*Location: \(.*\)/\1/p' | sed 's/[[:space:]]*$//')

if [ -z "$REDIRECT_URL" ]; then
    echo "Could not find redirect URL. Attempting to force reach portal.iob.de..." | tee -a "$LOG_FILE"
    REDIRECT_URL="http://portal.iob.de/"
fi

# Extract LOGIN_URL (Hotsplots auth URL) from query string
LOGIN_URL=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\(https%3a%2f%2f[^&]*\).*/\1/p' | sed 's/%3a/:/g;s/%2f/\//g;s/%26/\&/g;s/%3d/=/g')

echo "Extracted Hotsplots URL: $LOGIN_URL" | tee -a "$LOG_FILE"

# 3. Access Prelogin (Stage 1)
echo "Accessing prelogin step..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" "http://192.168.44.1/prelogin" >> "$LOG_FILE" 2>&1

# 4. Final Hotsplots Authorization (Stage 2)
echo "Performing final auth against Hotsplots..." | tee -a "$LOG_FILE"
# We use the extracted LOGIN_URL to POST the required auth parameters
# The portal expects to hit the Hotsplots auth endpoint after the local gateway prelogin
AUTH_RESPONSE=$(curl -k -v -A "$USER_AGENT" -d "username=&password=&button=Login" "$LOGIN_URL" 2>&1)

echo "Auth Response: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

# 5. Connectivity check
echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
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

# 2. Trigger initial redirect to capture portal parameters
echo "Fetching initial redirect to identify portal..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$USER_AGENT" -L http://neverssl.com 2>&1)
echo "Response captured." | tee -a "$LOG_FILE"

# Note: 'neverssl.com' is a utility site, not the portal itself. The portal is triggered by the network redirect.
# We need to hit the portal gateway directly. Based on the previous log, 192.168.44.1 is the gateway.

# 3. Access the portal and handle prelogin
echo "Accessing prelogin page..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" http://192.168.44.1/prelogin >> "$LOG_FILE" 2>&1

# 4. Handle the portal sequence
echo "Submitting portal acceptance..." | tee -a "$LOG_FILE"
# Using a cookie jar for session maintenance
COOKIE_FILE=$(mktemp)
curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -d "accept=1&submit=Connect" http://192.168.44.1/login >> "$LOG_FILE" 2>&1

# 5. Connectivity check
echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    rm "$COOKIE_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    rm "$COOKIE_FILE"
    exit 1
fi
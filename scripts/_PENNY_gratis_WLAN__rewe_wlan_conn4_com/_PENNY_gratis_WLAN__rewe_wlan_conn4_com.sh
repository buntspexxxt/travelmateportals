#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
echo "Starting portal login process..." | tee -a "$LOG_FILE"

# 1. Network Wait
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

# 2. Setup environment
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
trap 'rm -f "$HTML_OUT"' EXIT

# Capture effective URL to identify landing
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -w "%\{url_effective\}" -o "$HTML_OUT" "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# 3. Analyze HTML for Token
# Extract JSON embedded in the HTML for 'conn4.hotspot.wbsToken'
TOKEN_JSON=$(grep -o 'conn4.hotspot.wbsToken = {[^}]*}' "$HTML_OUT" | sed 's/conn4.hotspot.wbsToken = //')

if [ -z "$TOKEN_JSON" ]; then
    echo "Error: Could not extract wbsToken from portal page. Is the network already authorized?" | tee -a "$LOG_FILE"
    exit 1
fi

# The portal appears to be a client-side heavy 'conn4' system. 
# It relies on the browser to execute the JS which initiates the handshake.
# Since we are using curl, we manually emulate the likely POST request to the identifier endpoint.
# Based on the logs, the system follows a 302 redirect pattern after an identification signal.

echo "Attempting to POST identification to portal..." | tee -a "$LOG_FILE"
# Using the structure observed in the log: /ident?client_mac=...&client_ip=...&site_id=...&signature=...
# Note: Without a full JS execution engine, we hope a simple GET to the URL provided in the log is enough.
IDENT_URL=$(echo "$EFFECTIVE_URL" | sed -n 's|\(.*\)#|\1|p')ident?client_mac=E686AAAEA26E&client_ip=10.97.99.88&site_id=10143
echo "Submitting identification to: $IDENT_URL" | tee -a "$LOG_FILE"

RESPONSE_CODE=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%\{http_code\}" -m 15 "$IDENT_URL")
echo "HTTP Response from identification: $RESPONSE_CODE" | tee -a "$LOG_FILE"

# 4. Connectivity Check
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds."
exit 1
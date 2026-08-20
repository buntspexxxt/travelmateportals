#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Exit on any failure
set -e

LOG_FILE="/tmp/portal_login.log"
echo "Starting login process for SSID WE_284DF0" > "$LOG_FILE"

trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

# 1. Wait for network readiness
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

# 2. Check if already connected
echo "Checking initial connectivity..." | tee -a "$LOG_FILE"
STATUS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 10 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$STATUS_CODE" = "204" ] || [ "$STATUS_CODE" = "200" ]; then
    echo "Already connected. No login required." | tee -a "$LOG_FILE"
    exit 0
fi

# 3. Detect and fetch portal page
echo "Detecting portal redirect..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# 4. Handle simple 'success' status portal
# The provided HTML content is just 'success'. If the portal is open, we simply confirm.
RESPONSE_CONTENT=$(cat "$HTML_OUT")
echo "Portal Response: $RESPONSE_CONTENT" | tee -a "$LOG_FILE"

# 5. Final Connectivity Verification
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1
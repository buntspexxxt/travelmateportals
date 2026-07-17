#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Prepare temporary file for cookies and HTML output
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT

LOG_FILE="/tmp/portal_login.log"
echo "Starting portal login process..." | tee -a "$LOG_FILE"

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

# 2. Capture initial redirect parameters from a connectivity check
echo "Fetching initial portal redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_INFO=$(curl -k -L -w "%""{url_effective}""" -o "$HTML_OUT" -m 15 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "http://neverssl.com")

# Extract query string
QUERY_STRING=$(echo "$REDIRECT_INFO" | sed -n 's/.*\?\(.*\)/\1/p')
echo "Extracted Query String: $QUERY_STRING" | tee -a "$LOG_FILE"

# 3. Submit login POST request
# The portal HTML indicates a POST to /bluespot-oneclick/login
LOGIN_URL="https://portal.wificloud.network/bluespot-oneclick/login"
echo "Submitting POST request to $LOGIN_URL..." | tee -a "$LOG_FILE"

RESPONSE_CODE=$(curl -k -L -s -o "$HTML_OUT" -w "%{http_code}" -m 15 \
    -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    --data-urlencode "session=" \
    "$LOGIN_URL")

echo "HTTP Response Code: $RESPONSE_CODE" | tee -a "$LOG_FILE"

# 4. Final Internet Connectivity Check
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
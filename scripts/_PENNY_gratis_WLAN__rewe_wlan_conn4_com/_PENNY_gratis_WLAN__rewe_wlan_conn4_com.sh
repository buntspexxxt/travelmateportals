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
    i=$(($i + 1))
done

# 2. Setup environment
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
HTML_OUT=$(mktemp)
trap 'rm -f "$HTML_OUT"' EXIT

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_OUT" "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# 3. Extract Token and Submit
# Token is inside conn4.hotspot.wbsToken in the HTML
TOKEN=$(grep -o 'wbsToken = {[^}]*}' "$HTML_OUT" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

if [ -z "$TOKEN" ]; then
    echo "Error: Could not extract wbsToken." | tee -a "$LOG_FILE"
    exit 1
fi

# The portal requires hitting the grant endpoint with the token
# The token contains base64 encoded auth parameters
API_HOST=$(echo "$EFFECTIVE_URL" | awk -F/ '{print $3}')
GRANT_URL="https://$API_HOST/grant"

echo "Submitting token to $GRANT_URL..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" -m 15 --data-urlencode "token=$TOKEN" "$GRANT_URL")
echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

# 4. Connectivity Check
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$(($i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established."
exit 1
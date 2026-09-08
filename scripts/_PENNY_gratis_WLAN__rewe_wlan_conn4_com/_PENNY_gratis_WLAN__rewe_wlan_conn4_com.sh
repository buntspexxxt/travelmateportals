#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting REWE/Conn4 portal login..." | tee -a "$LOG_FILE"

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
    i=$((i + 1))
done

COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching portal landing..." | tee -a "$LOG_FILE"
curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_OUT" -m 15 "http://neverssl.com" > /dev/null 2>&1

TOKEN=$(sed -n 's/.*"token":"\([a-zA-Z0-9+/=]\{50,\}\)".*/\1/p' "$HTML_OUT" | head -n 1 | sed 's/\r//g')

if [ -z "$TOKEN" ]; then
    echo "Error: Could not extract wbsToken." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Extracted Token: $TOKEN" | tee -a "$LOG_FILE"

# Conn4 hotspots usually require a POST to the /grant endpoint of the host
API_HOST="rewe-wlan.conn4.com"
GRANT_URL="https://$API_HOST/grant"

echo "Sending authorization request..." | tee -a "$LOG_FILE"
JSON_PAYLOAD=$(printf '{"token":"%s"}' "$TOKEN")

RESPONSE_CODE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -d "$JSON_PAYLOAD" -m 15 "$GRANT_URL")
echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

if [ "$RESPONSE_CODE" != "200" ] && [ "$RESPONSE_CODE" != "302" ]; then
   echo "Attempting fallback POST to root..." | tee -a "$LOG_FILE"
   curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -o /dev/null -d "token=$TOKEN" -m 15 "https://$API_HOST/" > /dev/null 2>&1
fi

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE)." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Connection not established." | tee -a "$LOG_FILE"
exit 1
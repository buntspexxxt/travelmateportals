#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/wifi_login.log"
COOKIE_JAR=$(mktemp)
HTML_OUT=$(mktemp)
trap 'rm -f "$COOKIE_JAR" "$HTML_OUT"' EXIT

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
    i=$((i + 1))
done

echo "Fetching initial portal page..."
curl -k -L -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o "$HTML_OUT" "http://neverssl.com" >/dev/null 2>&1

echo "Extracting WBS Token from HTML..."
TOKEN=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')
if [ -z "$TOKEN" ]; then
    echo "ERROR: Token extraction failed." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Attempting to start scene session..."
# Based on the HTML, the portal expects to load a scene via an internal API
RESPONSE=$(curl -k -X POST -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H "Content-Type: application/json" \
    -d "{"token":"$TOKEN"}" \
    -m 15 -w "
HTTP_CODE:%{http_code}" "https://469.rdr.conn4.com/wbs/api/v1/sessions")

echo "Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying internet connectivity..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Connected." | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected (Code: $CHECK_CODE)." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

exit 1
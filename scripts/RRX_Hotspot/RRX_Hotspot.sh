#!/bin/sh
# SCRIPT_VERSION="1.0.0"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
LOG_FILE="/tmp/portal_log.txt"

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

echo "Fetching initial redirect to extract parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%""{url_effective}" -o "$HTML_OUT" -m 15 "http://neverssl.com")

echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*loginurl=\([^ ]*\)/\1/p')
# Decode URL encoded string if necessary, but here we can extract parameters directly from the loginurl
# The structure follows CoovaChilli/Hotspot login format
CHALLENGE=$(echo "$QUERY_STRING" | sed -n 's/.*challenge=\([^&]*\).*/\1/p' | sed 's/%3d/=/g')
UAMIP=$(echo "$QUERY_STRING" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$QUERY_STRING" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')

echo "Challenge identified: $CHALLENGE" | tee -a "$LOG_FILE"

# Construct the login URL based on common Hotspot/CoovaChilli architecture
LOGIN_URL="http://$UAMIP:$UAMPORT/logon"

echo "Submitting form to $LOGIN_URL" | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -m 15 --data-urlencode "username=" --data-urlencode "password=" --data-urlencode "challenge=$CHALLENGE" -w "
HTTP_CODE:%{http_code}" "$LOGIN_URL")

echo "$RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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
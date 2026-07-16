#!/bin/sh
# SCRIPT_VERSION="1.6.0"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}" "${HTML_OUT:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
HTML_OUT=$(mktemp)
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Portal Login Process..." | tee -a "$LOG_FILE"

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

perform_curl() {
    curl -m 15 -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$@"
}

echo "Step 1: Identifying redirect parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -m 15 -k -L -A "$USER_AGENT" -w "%{url_effective}" -o /dev/null "http://neverssl.com")
# Extract the Hotsplots redirect query string directly from the initial portal redirect
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*loginurl=https%3A%2F%2Fwww.hotsplots.de%2Fauth%2Flogin.php%3F\(.*\)/\1/p' | sed 's/%3D/=/g;s/%26/\&/g')

echo "Step 2: Accessing Landing Page to trigger session..." | tee -a "$LOG_FILE"
perform_curl -o "$HTML_OUT" "http://portal.iob.de"

echo "Step 3: Triggering prelogin on gateway..." | tee -a "$LOG_FILE"
perform_curl -o "$HTML_OUT" "http://192.168.44.1/prelogin"

echo "Step 4: Executing Hotsplots authentication..." | tee -a "$LOG_FILE"
AUTH_URL="https://www.hotsplots.de/auth/login.php?$QUERY_STRING"
# Submit post to grant access
RESPONSE=$(perform_curl -X POST --data-urlencode "button=Login" "$AUTH_URL")
echo "HTTP Response from auth: $RESPONSE" | tee -a "$LOG_FILE"

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
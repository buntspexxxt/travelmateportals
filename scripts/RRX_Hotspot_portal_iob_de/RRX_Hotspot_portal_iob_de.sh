#!/bin/bash
# SCRIPT_VERSION="1.3.1"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Portal Login Process..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

perform_curl() {
    curl -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$@"
}

echo "Step 1: Identifying redirect parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -o /dev/null -w "%{url_effective}" "http://neverssl.com")
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*loginurl=https%3A%2F%2Fwww.hotsplots.de%2Fauth%2Flogin.php%3F\(.*\)/\1/p' | sed 's/%3D/=/g;s/%26/\&/g')

echo "Step 2: Accessing Landing Page..." | tee -a "$LOG_FILE"
perform_curl "http://portal.iob.de"

echo "Step 3: Triggering prelogin..." | tee -a "$LOG_FILE"
perform_curl "http://192.168.44.1/prelogin"

echo "Step 4: Executing Hotsplots authentication..." | tee -a "$LOG_FILE"
AUTH_URL="https://www.hotsplots.de/auth/login.php?$QUERY_STRING"
# The portal requires the 'button' field to trigger the session
RESPONSE=$(perform_curl -X POST -d "button=Login" "$AUTH_URL")
echo "Auth Response Code: $?" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_log.txt"
COOKIE_FILE=$(mktemp)
echo "Starting RRX login script..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup portal.iob.de >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Initiating portal sequence..." | tee -a "$LOG_FILE"
# First step: The portal redirects to the landing page which contains the /prelogin link
# We follow redirects and capture cookies
RESPONSE_CODE=$(curl -m 15 -k -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" "http://192.168.44.1")
echo "Landing Page HTTP Status: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Following /prelogin link..." | tee -a "$LOG_FILE"
# Based on the provided HTML, the next step is a GET to /prelogin
FINAL_URL=$(curl -m 15 -k -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -w "%{url_effective}" -o /dev/null "http://192.168.44.1/prelogin")
echo "Effective URL after prelogin: $FINAL_URL" | tee -a "$LOG_FILE"

sleep 5

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_JAR="/tmp/db_cookies.txt"
DOMAIN="wifi.bahn.de"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Fetching initial session cookie and CSRF token from https://${DOMAIN}/en/" | tee -a "$LOG_FILE"
curl -v -k -A "$USER_AGENT" -c "$COOKIE_JAR" "https://${DOMAIN}/en/" > /dev/null 2>> "$LOG_FILE"

SEC_TOKEN=$(awk '/csrf/{print $7}' "$COOKIE_JAR" | sed "s/\r//g" | head -n 1)
if [ -z "$SEC_TOKEN" ]; then
    echo "Failed to extract CSRF token. Checking fallback..." | tee -a "$LOG_FILE"
    SEC_TOKEN=$(grep -o '"CSRFToken": "[^"]*"' /tmp/db_landing.html | cut -d'"' -f4 | head -n 1)
fi
echo "Extracted CSRF token: $SEC_TOKEN" | tee -a "$LOG_FILE"

echo "Submitting login POST request..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -H "Cookie: csrf=$SEC_TOKEN" \
     --data "login=true&CSRFToken=$SEC_TOKEN" \
     "https://${DOMAIN}/en/" 2>&1)

echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
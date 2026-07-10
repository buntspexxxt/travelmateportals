#!/bin/bash
# SCRIPT_VERSION="1.1.0"

trap 'rm -f "${COOKIE_JAR:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="$(mktemp)"
HTML_FILE="$(mktemp)"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
DOMAIN="wifi.bahn.de"

# Handle SSL Renegotiation issue encountered in previous logs by using --ciphers DEFAULT@SECLEVEL=0
CURL_OPTS="-k -L -A "$USER_AGENT" --ciphers DEFAULT@SECLEVEL=0"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Fetching initial session cookie from https://${DOMAIN}/en/" | tee -a "$LOG_FILE"
curl -m 15 -k -v $CURL_OPTS -c "$COOKIE_JAR" -o "$HTML_FILE" "https://${DOMAIN}/en/" 2>> "$LOG_FILE"

# Extract CSRF token from cookies or HTML as per travelmate logic
SEC_TOKEN=$(grep 'csrf' "$COOKIE_JAR" | awk '{print $7}')
if [ -z "$SEC_TOKEN" ]; then
    SEC_TOKEN=$(sed -n 's/.*CSRFToken.*value="\([^"]*\)".*/\1/p' "$HTML_FILE" | head -n 1)
fi
echo "Extracted CSRF token: $SEC_TOKEN" | tee -a "$LOG_FILE"

if [ -z "$SEC_TOKEN" ]; then
    echo "Failed to extract CSRF token. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting login POST request..." | tee -a "$LOG_FILE"
# Using the logic confirmed by travelmate/OpenWrt implementation
HTTP_STATUS=$(curl -m 15 -k -v $CURL_OPTS -b "$COOKIE_JAR" -H "Cookie: csrf=$SEC_TOKEN" --data "login=true&CSRFToken=$SEC_TOKEN" -w "%{http_code}" -o /dev/null "https://${DOMAIN}/en/" 2>> "$LOG_FILE")
echo "HTTP Response: $HTTP_STATUS" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
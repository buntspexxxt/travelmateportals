#!/bin/bash
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_JAR:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="$(mktemp)"
HTML_FILE="$(mktemp)"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
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
curl -v -k -A "$USER_AGENT" -c "$COOKIE_JAR" -o "$HTML_FILE" "https://${DOMAIN}/en/" 2>> "$LOG_FILE"

SEC_TOKEN=$(grep -o 'name="CSRFToken" value="[^"]*"' "$HTML_FILE" | sed 's/.*value="\([^"]*\)".*/\1/' | head -n 1)
if [ -z "$SEC_TOKEN" ]; then
    SEC_TOKEN=$(grep -o '"CSRFToken":"[^"]*"' "$HTML_FILE" | cut -d'"' -f4 | head -n 1)
fi
echo "Extracted CSRF token: $SEC_TOKEN" | tee -a "$LOG_FILE"

echo "Submitting login POST request..." | tee -a "$LOG_FILE"
curl -v -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -H "Referer: https://${DOMAIN}/en/" \
     --data "login=true&CSRFToken=${SEC_TOKEN}" \
     "https://${DOMAIN}/en/" > /dev/null 2>> "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
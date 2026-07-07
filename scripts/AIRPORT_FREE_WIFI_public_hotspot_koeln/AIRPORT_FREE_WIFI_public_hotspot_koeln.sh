#!/bin/bash
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
echo "Starting portal login sequence..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching initial landing page..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null -s "https://public.hotspot.koeln/cp/guqs6n9d"

echo "Submitting login form with checkbox agreement..." | tee -a "$LOG_FILE"
# The portal requires accepting terms. Submitting 'login=oneclick' with checkbox checked.
RESPONSE_CODE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -d "login=oneclick" \
  -d "customControlValidation1=on" \
  -o /dev/null -w "%{http_code}" "https://public.hotspot.koeln/login")

echo "HTTP Response Code: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
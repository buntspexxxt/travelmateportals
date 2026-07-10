#!/bin/bash
# SCRIPT_VERSION="1.3.1"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
echo "Starting updated portal login sequence..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Step 1: Fetching landing page..." | tee -a "$LOG_FILE"
REDIRECT_URL="https://public.hotspot.koeln/cp/guqs6n9d"
EFFECTIVE_URL=$(curl -m 15 -k -L --connect-timeout 10 --max-time 25 -w "%{url_effective}" -o "$HTML_FILE" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" "$REDIRECT_URL")

# Extracting hidden fields and login URL
FORM_ACTION=$(sed -n 's/.*action="\([^"]*\)".*/\1/p' "$HTML_FILE" | head -n1 | tr -d '\015')
[ -z "$FORM_ACTION" ] && FORM_ACTION="https://public.hotspot.koeln/login"

echo "Step 2: Submitting login with mandatory checkbox..." | tee -a "$LOG_FILE"
# Based on HTML, we must include the checkbox 'required' or the form fails. 
# The portal logic checks for presence of fields. Adding checkbox validation parameter if necessary.
# Sending form data. Note: The checkbox is 'id="customControlValidation1"'. In POST, it usually expects the field to be present.
curl -m 15 -k -L --connect-timeout 15 --max-time 30 -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -d "login=oneclick" \
  -d "customControlValidation1=on" \
  "$FORM_ACTION"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
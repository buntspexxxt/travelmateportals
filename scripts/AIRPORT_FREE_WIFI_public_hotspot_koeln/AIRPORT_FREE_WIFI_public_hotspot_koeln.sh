#!/bin/bash
# SCRIPT_VERSION="1.2.0"
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
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
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
echo "Fetching landing page..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -v -L -w "%{url_effective}" -o "$HTML_FILE" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" "http://neverssl.com" 2>&1 | grep "Location:" | tail -n1 | cut -d' ' -f2 | tr -d '\015')
[ -z "$REDIRECT_URL" ] && REDIRECT_URL="https://public.hotspot.koeln/cp/guqs6n9d"
HOST=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
FORM_ACTION=$(sed -n 's/.*action="\([^"]*\)".*/\1/p' "$HTML_FILE" | head -n1)
[ -z "$FORM_ACTION" ] && FORM_ACTION="/login"
[[ "$FORM_ACTION" != http* ]] && LOGIN_URL="${HOST}${FORM_ACTION}" || LOGIN_URL="$FORM_ACTION"
echo "Submitting form to: $LOGIN_URL" | tee -a "$LOG_FILE"
REDIRECT_SUCCESS=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "login=oneclick" -d "customControlValidation1=on" -w "%{redirect_url}" -o /dev/null "$LOGIN_URL" | tr -d '\015')
echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
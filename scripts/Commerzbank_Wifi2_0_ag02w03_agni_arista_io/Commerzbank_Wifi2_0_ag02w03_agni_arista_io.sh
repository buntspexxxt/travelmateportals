#!/bin/bash
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/captive_portal_login.log"

echo "Starting Commerzbank Portal Login" | tee -a "$LOG_FILE"

echo "Waiting for network..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready!" | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
done

COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching landing page to capture session parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -m 15 -k -L -A "$UA" -c "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_FILE" "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

BASE_URL=$(echo "$EFFECTIVE_URL" | cut -d'/' -f1-3)

# Based on the requirement to 'scroll to bottom' to accept terms:
# This usually implies a POST request to an API endpoint like /api/v1/login or /auth/accept
# Arista/Agni portals often use /api/portal/login

LOGIN_API="${BASE_URL}/api/portal/login"

echo "Sending acceptance POST to $LOGIN_API" | tee -a "$LOG_FILE"

# We attempt to send a JSON payload indicating acceptance of terms
HTTP_STATUS=$(curl -m 15 -k -s -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -X POST "$LOGIN_API" \
    -H "Content-Type: application/json" \
    -d '{"accept_terms": true, "action": "login"}' \
    -w "%{http_code}" -o /dev/null)

echo "HTTP Response Status: $HTTP_STATUS" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
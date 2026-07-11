#!/bin/bash
# SCRIPT_VERSION="1.1.0"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/captive_portal_login.log"

echo "Starting Commerzbank Portal Login" | tee -a "$LOG_FILE"

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

COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching landing page to capture session parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -m 15 -k -L -A "$UA" -c "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_FILE" "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extract domain dynamically
BASE_URL=$(echo "$EFFECTIVE_URL" | cut -d'/' -f1-3)
QUERY_STRING=$(echo "$EFFECTIVE_URL" | grep -o '\?.*' | cut -c 2-)

# Step 1: Login/Acceptance
LOGIN_API="${BASE_URL}/api/portal/login"
echo "Sending initial acceptance POST to $LOGIN_API" | tee -a "$LOG_FILE"

HTTP_STATUS=$(curl -m 15 -k -s -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -X POST "$LOGIN_API" \
    -H "Content-Type: application/json" \
    -d '{"accept_terms":true,"action":"login"}' \
    -w "%{http_code}" -o /dev/null)

echo "HTTP Response Status: $HTTP_STATUS" | tee -a "$LOG_FILE"

# Step 2: Often Arista/Agni portals require a follow-up 'auth' check or trigger after the redirect
# We check for a secondary authentication path if the first step returns a 302 or partial state
AUTH_CHECK="${BASE_URL}/api/portal/auth"
echo "Performing secondary auth check at $AUTH_CHECK" | tee -a "$LOG_FILE"
curl -m 15 -k -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X GET "$AUTH_CHECK" >> "$LOG_FILE" 2>&1

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
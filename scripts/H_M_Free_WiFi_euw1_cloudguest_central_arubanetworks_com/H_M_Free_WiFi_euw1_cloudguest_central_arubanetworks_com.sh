#!/bin/sh
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting H&M Free WiFi authentication process" | tee -a "$LOG_FILE"

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

echo "Fetching initial portal URL..." | tee -a "$LOG_FILE"
# Extract URL from the redirect page response
INITIAL_PAGE_CONTENT=$(curl -k -A "$USER_AGENT" -L -c "$COOKIE_FILE" "http://neverssl.com")
LOGIN_URL=$(echo "$INITIAL_PAGE_CONTENT" | sed -n 's/.*URL=\([^"]*\)".*/\1/p' | tr -d '\015')

if [ -z "$LOGIN_URL" ]; then
    echo "Failed to extract LOGIN_URL, trying capture URL..." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Navigating to login page: $LOGIN_URL" | tee -a "$LOG_FILE"
LOGIN_HTML=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LOGIN_URL")

echo "Submitting acceptance..." | tee -a "$LOG_FILE"
# Extract form action and dynamic tokens
FORM_ACTION=$(echo "$LOGIN_HTML" | sed -n 's/.*action="\([^"]*\)".*/\1/p')
# Ensure absolute URL
if [ "${FORM_ACTION#/}" != "$FORM_ACTION" ]; then
    BASE_URL=$(echo "$LOGIN_URL" | cut -d/ -f1-3)
    FORM_ACTION="${BASE_URL}${FORM_ACTION}"
fi

# Extract all hidden fields dynamically
POST_DATA=$(echo "$LOGIN_HTML" | sed -n 's/.*name="\([^"]*\)" value="\([^"]*\)".*/\1=\2/p' | paste -sd '&' -)

echo "Posting data to $FORM_ACTION" | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "${POST_DATA}&accept=true" -X POST "$FORM_ACTION"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
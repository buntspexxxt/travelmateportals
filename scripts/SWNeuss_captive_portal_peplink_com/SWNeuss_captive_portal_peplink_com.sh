#!/bin/bash
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
echo "Starting Peplink Captive Portal Login" | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null -w "%{redirect_url}" http://detectportal.firefox.com/success.txt | sed "s/\r//g")
BASE_URL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
QUERY_STRING=$(echo "$REDIRECT_URL" | sed -n "s/.*\?//p")
echo "Redirect URL detected: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Querying session/resume API..." | tee -a "$LOG_FILE"
API_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$BASE_URL/cp/session/resume?$QUERY_STRING")
echo "API Response: $API_RESPONSE" | tee -a "$LOG_FILE"

# Handle logic from HTML: Check if is_prompt_sign_in is true
IS_PROMPT=$(echo "$API_RESPONSE" | sed -n 's/.*"is_prompt_sign_in":\([^,}]*\).*/\1/p' | sed 's/ //g')
echo "Is Prompt Required: $IS_PROMPT" | tee -a "$LOG_FILE"

# Even if not prompted, we attempt to trigger the login flow found in JS/HTML analysis
echo "Triggering login sequence..." | tee -a "$LOG_FILE"
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?$QUERY_STRING&resume=true&command=login"
FINAL_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LOGIN_URL")
echo "Final Action HTTP Response: $FINAL_RESPONSE" | tee -a "$LOG_FILE"

sleep 5

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
echo "Starting Enhanced Peplink Portal Login" | tee -a "$LOG_FILE"

# 1. Wait for Network
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

# 2. Extract Session/Resume Data
echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null -w "%{redirect_url}" http://detectportal.firefox.com/success.txt | sed "s/\\r//g")
echo "Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

# 3. Resume Session
echo "Querying session/resume API..." | tee -a "$LOG_FILE"
# Dynamic base path from redirect
BASE_URL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
QUERY_STRING=$(echo "$REDIRECT_URL" | sed -n "s/.*\\?//p")

API_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$BASE_URL/cp/session/resume?$QUERY_STRING")
echo "API Response: $API_RESPONSE" | tee -a "$LOG_FILE"

# 4. Handle Logic (Connect Button Case)
# If API says is_prompt_sign_in is true, we must simulate the button click
IS_PROMPT=$(echo "$API_RESPONSE" | sed -n "s/.*\\"is_prompt_sign_in\\":\\\?\\([^,}\\]*\\).*/\\1/p")
echo "Is Prompt Required: $IS_PROMPT" | tee -a "$LOG_FILE"

if [ "$IS_PROMPT" == "true" ]; then
    echo "Portal requires interaction (Connect to Internet). Triggering login..." | tee -a "$LOG_FILE"
    # Build the login call as per packed.js 'makeResumeLoginCall'
    LOGIN_URL="$BASE_URL/cp/login?$QUERY_STRING&resume=true&command=login"
    FINAL_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LOGIN_URL")
    echo "Final Action HTTP Response: $FINAL_RESPONSE" | tee -a "$LOG_FILE"
fi

# 5. Smart Wait
sleep 5

# 6. Verify connectivity
echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
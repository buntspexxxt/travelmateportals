#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting login process" | tee -a "$LOG_FILE"

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
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching portal landing page to extract tokens..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
# Use the redirect URL discovered in previous logs to ensure correct context
RESPONSE=$(curl -m 15 -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_OUT" "https://auth.hotsplots.de/login?res=notyet")
echo "Initial page fetched: $RESPONSE" | tee -a "$LOG_FILE"

# Extracting hidden fields from the form
HTML_CONTENT=$(cat "$HTML_OUT")
CHALLENGE=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[challenge\]" value="\([^"]*\)".*/\1/p')
TOKEN=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[_token\]" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[uamip\]" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[uamport\]" value="\([^"]*\)".*/\1/p')

echo "Extracted Tokens: Challenge=$CHALLENGE Token=$TOKEN" | tee -a "$LOG_FILE"

echo "Submitting login form..." | tee -a "$LOG_FILE"
POST_DATA="login_status_form%5Bbutton%5D=&login_status_form%5Bchallenge%5D=$CHALLENGE&login_status_form%5Buamip%5D=$UAMIP&login_status_form%5Buamport%5D=$UAMPORT&login_status_form%5Bll%5D=&login_status_form%5BmyLogin%5D=&login_status_form%5B_token%5D=$TOKEN"

SUBMIT_RESPONSE=$(curl -m 15 -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" -w "%{http_code}" -o /dev/null "https://auth.hotsplots.de/login")
echo "Submit HTTP Status: $SUBMIT_RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
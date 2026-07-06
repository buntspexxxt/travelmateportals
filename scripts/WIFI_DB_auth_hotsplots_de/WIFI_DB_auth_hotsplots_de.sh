#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies.txt"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Step 1: Fetching initial auth portal page..." | tee -a "$LOG_FILE"
# Fetching initial redirect to establish session and get parameters
INIT_RESPONSE=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L "http://wifi.bahn.de/")

echo "Step 2: Parsing hidden form parameters from HTML..." | tee -a "$LOG_FILE"
# Using sed to extract fields dynamically from the HTML body
HTML_CONTENT=$(echo "$INIT_RESPONSE")
CHALLENGE=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[challenge\]" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[uamip\]" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[uamport\]" value="\([^"]*\)".*/\1/p')
TOKEN=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[_token\]" value="\([^"]*\)".*/\1/p')

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to parse tokens. Check HTML structure." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Step 3: Submitting login form via POST..." | tee -a "$LOG_FILE"
# Constructing POST payload using extracted values
POST_DATA="login_status_form%5Bbutton%5D=Jetzt+kostenlos+surfen&login_status_form%5Bchallenge%5D=$CHALLENGE&login_status_form%5Buamip%5D=$UAMIP&login_status_form%5Buamport%5D=$UAMPORT&login_status_form%5Bll%5D=&login_status_form%5BmyLogin%5D=&login_status_form%5B_token%5D=$TOKEN"

SUBMIT_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" -L -o /dev/null -w "%{http_code}" "https://auth.hotsplots.de/login")

echo "Submission HTTP Code: $SUBMIT_RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
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

echo "Step 1: Accessing initial URL to trigger redirect..." | tee -a "$LOG_FILE"
INITIAL_CURL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L "http://neverssl.com" 2>&1)
REDIRECT_URL=$(echo "$INITIAL_CURL" | sed -n 's/.*Location: //p' | sed 's/\\r//g' | head -n 1)
echo "Redirecting to: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Step 2: Fetching portal page to extract hidden form fields..." | tee -a "$LOG_FILE"
HTML=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "$REDIRECT_URL")
echo "$HTML" > /tmp/portal.html

CHALLENGE=$(sed -n 's/.*id="login_status_form_challenge" value="\([^"]*\)".*/\1/p' /tmp/portal.html)
UAMIP=$(sed -n 's/.*id="login_status_form_uamip" value="\([^"]*\)".*/\1/p' /tmp/portal.html)
UAMPORT=$(sed -n 's/.*id="login_status_form_uamport" value="\([^"]*\)".*/\1/p' /tmp/portal.html)
TOKEN=$(sed -n 's/.*id="login_status_form__token" value="\([^"]*\)".*/\1/p' /tmp/portal.html)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to extract hidden tokens. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Step 3: Submitting acceptance form..." | tee -a "$LOG_FILE"
# The form uses specific field names for Hotsplots login
POST_DATA="login_status_form%5Bbutton%5D=Jetzt+kostenlos+surfen&login_status_form%5Bchallenge%5D=$CHALLENGE&login_status_form%5Buamip%5D=$UAMIP&login_status_form%5Buamport%5D=$UAMPORT&login_status_form%5Bll%5D=&login_status_form%5BmyLogin%5D=&login_status_form%5B_token%5D=$TOKEN"

SUBMIT=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" -L "$REDIRECT_URL" 2>&1)
echo "Submission result: $SUBMIT" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi

#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Step 1: Fetching initial redirect to get dynamic parameters..." | tee -a "$LOG_FILE"
# Extract initial redirect parameters from the portal location
INITIAL_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -L "http://neverssl.com" 2>&1)
REDIRECT_URL=$(echo "$INITIAL_RESPONSE" | sed -n 's/.*Location: //p' | tr -d '\r' | head -n 1)

echo "Step 2: Accessing login page with parameters to retrieve form tokens..." | tee -a "$LOG_FILE"
HTML=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -L "$REDIRECT_URL" 2>&1)
echo "$HTML" > /tmp/portal_html.txt

# Extract hidden tokens using POSIX sed
CHALLENGE=$(sed -n 's/.*id="login_status_form_challenge" value="\([^"]*\)".*/\1/p' /tmp/portal_html.txt)
UAMIP=$(sed -n 's/.*id="login_status_form_uamip" value="\([^"]*\)".*/\1/p' /tmp/portal_html.txt)
UAMPORT=$(sed -n 's/.*id="login_status_form_uamport" value="\([^"]*\)".*/\1/p' /tmp/portal_html.txt)
TOKEN=$(sed -n 's/.*id="login_status_form__token" value="\([^"]*\)".*/\1/p' /tmp/portal_html.txt)

if [ -z "$TOKEN" ]; then
    echo "Error: Failed to extract hidden tokens. Check logs." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Step 3: Submitting acceptance form..." | tee -a "$LOG_FILE"
# Construct POST data exactly as expected by the form
POST_DATA="login_status_form%5Bbutton%5D=Jetzt+kostenlos+surfen&login_status_form%5Bchallenge%5D=$CHALLENGE&login_status_form%5Buamip%5D=$UAMIP&login_status_form%5Buamport%5D=$UAMPORT&login_status_form%5Bll%5D=&login_status_form%5BmyLogin%5D=&login_status_form%5B_token%5D=$TOKEN"

SUBMIT_RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -d "$POST_DATA" "$REDIRECT_URL" 2>&1)
echo "HTTP Response: $SUBMIT_RESPONSE" | tee -a "$LOG_FILE"

echo "Form submitted. Checking connectivity..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >/dev/null && { echo "Success: Internet access confirmed." | tee -a "$LOG_FILE"; exit 0; } || { echo "Failure: No internet access detected." | tee -a "$LOG_FILE"; exit 1; }
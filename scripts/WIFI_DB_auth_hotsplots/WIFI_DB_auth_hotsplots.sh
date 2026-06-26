#!/bin/bash
LOG_FILE="/tmp/portal_log.txt"
COOKIE_FILE="/tmp/portal_cookies.txt"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching captive portal page to extract tokens..." | tee -a "$LOG_FILE"
# Using -L to follow redirects
RESPONSE=$(curl -v -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L "http://detectportal.firefox.com/success.txt" 2>&1)

# Extract base URL and parameters
LOGIN_URL=$(echo "$RESPONSE" | grep -o 'https://auth.hotsplots.de/login?[^ ]*')
if [ -z "$LOGIN_URL" ]; then
    echo "Failed to find login URL. Manual intervention may be required." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Login URL identified: $LOGIN_URL" | tee -a "$LOG_FILE"

# Download portal body to extract hidden form fields
HTML_CONTENT=$(curl -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L "$LOGIN_URL")

TOKEN=$(echo "$HTML_CONTENT" | grep -oP 'name="login_status_form\[_token\]" value="\K[^"]+')
CHALLENGE=$(echo "$HTML_CONTENT" | grep -oP 'name="login_status_form\[challenge\]" value="\K[^"]+')
UAMIP=$(echo "$HTML_CONTENT" | grep -oP 'name="login_status_form\[uamip\]" value="\K[^"]+')
UAMPORT=$(echo "$HTML_CONTENT" | grep -oP 'name="login_status_form\[uamport\]" value="\K[^"]+')

# Prepare POST payload
POST_DATA="login_status_form%5Bbutton%5D=Jetzt+kostenlos+surfen&login_status_form%5Bchallenge%5D=$CHALLENGE&login_status_form%5Buamip%5D=$UAMIP&login_status_form%5Buamport%5D=$UAMPORT&login_status_form%5Bll%5D=&login_status_form%5BmyLogin%5D=&login_status_form%5B_token%5D=$TOKEN"

echo "Submitting login form..." | tee -a "$LOG_FILE"
SUBMIT=$(curl -v -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -d "$POST_DATA" "$LOGIN_URL" 2>&1)

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." | tee -a "$LOG_FILE" || { echo "Error: No internet access."; exit 1; }
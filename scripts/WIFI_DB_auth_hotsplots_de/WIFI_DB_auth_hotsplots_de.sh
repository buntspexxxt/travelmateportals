#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
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

echo "Fetching initial portal redirect..." | tee -a "$LOG_FILE"
# Using -v to see headers, capturing response
REDIRECT_URL=$(curl -v -A "$UA" -L "http://neverssl.com" 2>&1 | grep -i "< Location:" | sed -n 's/.*Location: //p' | tr -d '\r' | head -n 1)

if [ -z "$REDIRECT_URL" ]; then
    echo "Failed to find redirect URL. Portal might already be authenticated." | tee -a "$LOG_FILE"
    exit 0
fi

echo "Redirect URL extracted: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Downloading portal page to extract hidden fields..." | tee -a "$LOG_FILE"
curl -v -A "$UA" -c /tmp/cookies.txt "$REDIRECT_URL" > /tmp/portal.html 2>&1

# Extracting values
TOKEN=$(grep -oP 'name="login_status_form\[_token\]" value="\K[^"]+' /tmp/portal.html)
CHALLENGE=$(grep -oP 'name="login_status_form\[challenge\]" value="\K[^"]+' /tmp/portal.html)
UAMIP=$(grep -oP 'name="login_status_form\[uamip\]" value="\K[^"]+' /tmp/portal.html)
UAMPORT=$(grep -oP 'name="login_status_form\[uamport\]" value="\K[^"]+' /tmp/portal.html)

echo "Fields extracted: TOKEN=$TOKEN, CHALLENGE=$CHALLENGE" | tee -a "$LOG_FILE"

echo "Submitting login form..." | tee -a "$LOG_FILE"
# Based on Hotsplots standard flow
RESPONSE=$(curl -v -A "$UA" -b /tmp/cookies.txt -c /tmp/cookies.txt -L -d "login_status_form%5Bbutton%5D=Jetzt+kostenlos+surfen" -d "login_status_form%5Bchallenge%5D=$CHALLENGE" -d "login_status_form%5Buamip%5D=$UAMIP" -d "login_status_form%5Buamport%5D=$UAMPORT" -d "login_status_form%5B_token%5D=$TOKEN" "$REDIRECT_URL" 2>&1)

echo "Login submission complete." | tee -a "$LOG_FILE"

echo "Performing connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully authenticated!" || { echo "Authentication failed." && exit 1; }
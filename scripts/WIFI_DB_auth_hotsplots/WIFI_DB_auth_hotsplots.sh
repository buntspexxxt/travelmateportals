#!/bin/bash
LOG_FILE="/tmp/portal_auth.log"
COOKIE_FILE="/tmp/cookies.txt"
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

echo "Fetching initial redirect URL..." | tee -a "$LOG_FILE"
LANDING_RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o /tmp/portal.html -w "%{url_effective}" http://detectportal.firefox.com/success.txt 2>&1)
EFFECTIVE_URL=$(echo "$LANDING_RESPONSE" | grep "Location:" | tail -n1 | awk '{print $2}' | tr -d '\r')
[ -z "$EFFECTIVE_URL" ] && EFFECTIVE_URL="https://auth.hotsplots.de/login" 

echo "Extracted URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Extracting hidden form fields..." | tee -a "$LOG_FILE"
CHALLENGE=$(grep -o 'name="login_status_form\[challenge\]" value="[^"]*"' /tmp/portal.html | cut -d'"' -f4)
UAMIP=$(grep -o 'name="login_status_form\[uamip\]" value="[^"]*"' /tmp/portal.html | cut -d'"' -f4)
UAMPORT=$(grep -o 'name="login_status_form\[uamport\]" value="[^"]*"' /tmp/portal.html | cut -d'"' -f4)
TOKEN=$(grep -o 'name="login_status_form\[_token\]" value="[^"]*"' /tmp/portal.html | cut -d'"' -f4)

POST_DATA="login_status_form%5Bchallenge%5D=$CHALLENGE&login_status_form%5Buamip%5D=$UAMIP&login_status_form%5Buamport%5D=$UAMPORT&login_status_form%5Bbutton%5D=&login_status_form%5B_token%5D=$TOKEN"

echo "Submitting login form..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" "$EFFECTIVE_URL" 2>&1)
echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

sleep 5
echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "SUCCESS" && exit 0 || exit 1
#!/bin/bash
LOG_FILE="/tmp/portal_auth.log"
COOKIE_FILE="/tmp/cookies.txt"
HTML_FILE="/tmp/portal.html"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting Auth Process" | tee -a "$LOG_FILE"

# 1. DHCP Wait
echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found." | tee -a "$LOG_FILE"; break; fi
    sleep 1
done

# 2. Get Initial Page
echo "Fetching portal page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o "$HTML_FILE" -w "%{url_effective}" http://detectportal.firefox.com/success.txt 2>&1 | grep "Location:" | tail -n1 | awk '{print $2}' | tr -d '\r')
[ -z "$EFFECTIVE_URL" ] && EFFECTIVE_URL="https://auth.hotsplots.de/login"

# 3. Extract and Submit Form
echo "Extracting tokens and submitting..." | tee -a "$LOG_FILE"
CHALLENGE=$(grep -o 'name="login_status_form\[challenge\]" value="[^"]*"' "$HTML_FILE" | cut -d'"' -f4)
UAMIP=$(grep -o 'name="login_status_form\[uamip\]" value="[^"]*"' "$HTML_FILE" | cut -d'"' -f4)
UAMPORT=$(grep -o 'name="login_status_form\[uamport\]" value="[^"]*"' "$HTML_FILE" | cut -d'"' -f4)
TOKEN=$(grep -o 'name="login_status_form\[_token\]" value="[^"]*"' "$HTML_FILE" | cut -d'"' -f4)

POST_DATA="login_status_form%5Bchallenge%5D=$CHALLENGE&login_status_form%5Buamip%5D=$UAMIP&login_status_form%5Buamport%5D=$UAMPORT&login_status_form%5Bbutton%5D=Jetzt+kostenlos+surfen&login_status_form%5B_token%5D=$TOKEN"

echo "Sending POST request..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" "$EFFECTIVE_URL" 2>&1)
echo "Response status: $?" | tee -a "$LOG_FILE"

# 4. Connectivity Check
echo "Checking connectivity..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >/dev/null && echo "SUCCESS" && exit 0 || exit 1
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

echo "Fetching initial portal page to extract tokens..." | tee -a "$LOG_FILE"
# Initial request to a common redirect domain or the default gateway
HTML=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -L "http://neverssl.com" 2>&1)

# Extract the form action or use current URL
# Hotsplots portals generally POST to the URL the user lands on
LANDING_URL=$(echo "$HTML" | grep -o 'Location: [^ ]*' | tail -1 | sed -n 's/Location: //p' | tr -d '\r')
[ -z "$LANDING_URL" ] && LANDING_URL="https://auth.hotsplots.de/login"

# Get the page HTML to find hidden fields
HTML_CONTENT=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt "$LANDING_URL")

echo "Extracting hidden form fields..." | tee -a "$LOG_FILE"
CHALLENGE=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[challenge\]" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[uamip\]" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[uamport\]" value="\([^"]*\)".*/\1/p')
TOKEN=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[_token\]" value="\([^"]*\)".*/\1/p')

echo "Submitting login form..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt \
  -d "login_status_form%5Bbutton%5D=" \
  -d "login_status_form%5Bchallenge%5D=$CHALLENGE" \
  -d "login_status_form%5Buamip%5D=$UAMIP" \
  -d "login_status_form%5Buamport%5D=$UAMPORT" \
  -d "login_status_form%5B_token%5D=$TOKEN" \
  "$LANDING_URL")

echo "HTTP Response Received." | tee -a "$LOG_FILE"

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." || echo "Failure: Connectivity check failed." && exit 1

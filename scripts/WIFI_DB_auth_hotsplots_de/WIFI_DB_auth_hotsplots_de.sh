#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found." | tee -a "$LOG_FILE"; sleep 6; break; fi
    sleep 1
done

echo "Fetching portal index to extract CSRF tokens and form fields..." | tee -a "$LOG_FILE"
# Fetch landing page to get cookies and tokens
HTML_CONTENT=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -L "http://neverssl.com")

echo "Extracting dynamic hidden inputs..." | tee -a "$LOG_FILE"
# Using POSIX sed to extract values safely
CHALLENGE=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[challenge\]" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[uamip\]" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[uamport\]" value="\([^"]*\)".*/\1/p')
TOKEN=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[_token\]" value="\([^"]*\)".*/\1/p')

if [ -z "$TOKEN" ]; then
    echo "Error: Could not extract token. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting acceptance form with collected tokens..." | tee -a "$LOG_FILE"
# Submitting POST request to the auth server
RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt \
  -d "login_status_form[button]=" \
  -d "login_status_form[challenge]=$CHALLENGE" \
  -d "login_status_form[uamip]=$UAMIP" \
  -d "login_status_form[uamport]=$UAMPORT" \
  -d "login_status_form[_token]=$TOKEN" \
  "https://auth.hotsplots.de/login")

echo "HTTP Response Received." | tee -a "$LOG_FILE"

echo "Connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." || { echo "Failure: Internet access not detected."; exit 1; }
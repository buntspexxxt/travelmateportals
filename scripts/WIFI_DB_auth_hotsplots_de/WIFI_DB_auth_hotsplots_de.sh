#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found." | tee -a "$LOG_FILE"; sleep 6; break; fi
    sleep 1
done

echo "Step 1: Fetching initial redirect to get Session ID and parameters..." | tee -a "$LOG_FILE"
# Capture initial redirect and session cookie
INITIAL_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -L "http://neverssl.com" 2>&1)

echo "Step 2: Parsing landing page for hidden form fields..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -L "https://auth.hotsplots.de/login")

# Extract hidden tokens using POSIX sed
CHALLENGE=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[challenge\]" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[uamip\]" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[uamport\]" value="\([^"]*\)".*/\1/p')
TOKEN=$(echo "$HTML_CONTENT" | sed -n 's/.*name="login_status_form\[_token\]" value="\([^"]*\)".*/\1/p')

if [ -z "$TOKEN" ]; then
    echo "Error: Could not extract token from HTML. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Step 3: Submitting acceptance form..." | tee -a "$LOG_FILE"
# Submit form data extracted from the page
FINAL_RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt \
  -d "login_status_form[button]=" \
  -d "login_status_form[challenge]=$CHALLENGE" \
  -d "login_status_form[uamip]=$UAMIP" \
  -d "login_status_form[uamport]=$UAMPORT" \
  -d "login_status_form[_token]=$TOKEN" \
  "https://auth.hotsplots.de/login" 2>&1)

echo "HTTP Response Received." | tee -a "$LOG_FILE"

echo "Connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." || { echo "Failure: Internet access not detected."; exit 1; }
#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching initial portal redirect..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -L -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt "http://detectportal.firefox.com/success.txt" 2>&1)
echo "Response dump: $RESPONSE" | tee -a "$LOG_FILE"

EFFECTIVE_URL=$(echo "$RESPONSE" | grep -oE "https://lmc.telekom.de[^"]+" | head -n 1)
echo "Target URL identified: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Downloading portal HTML to extract form data..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt "$EFFECTIVE_URL")

# The form uses POST method to the URL. The HTML shows a password field 'authenticationCode'.
# Assuming this is an open Wi-Fi, we try submitting an empty string or ' ' if the server requires it.
echo "Submitting acceptance form..." | tee -a "$LOG_FILE"
SUBMIT_RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -X POST "$EFFECTIVE_URL" \
    -d "authenticationCode=" \
    -d "accept=true")

echo "HTTP Submission Response: $SUBMIT_RESPONSE" | tee -a "$LOG_FILE"

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success! Internet is reachable." | tee -a "$LOG_FILE" && exit 0 || exit 1
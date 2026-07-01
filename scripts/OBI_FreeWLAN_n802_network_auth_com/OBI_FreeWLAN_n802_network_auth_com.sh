#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Detecting redirect..." | tee -a "$LOG_FILE"
# Fetch landing page to get initial session and redirect parameters
REDIRECT_INFO=$(curl -v -A "$USER_AGENT" -L "http://neverssl.com" 2>&1)
LANDING_URL=$(echo "$REDIRECT_INFO" | sed -n 's/.*Location: //p' | tr -d '\\r' | head -n 1)
echo "Landing URL: $LANDING_URL" | tee -a "$LOG_FILE"

echo "Fetching splash page..." | tee -a "$LOG_FILE"
PAGE_HTML=$(curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "$LANDING_URL")

echo "Executing XMLHttpRequest handshake to get 'Continue-Url' header..." | tee -a "$LOG_FILE"
# The portal requires an AJAX call to the HEAD of the current URL to get the 'Continue-Url' header
HANDSHAKE=$(curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt -X HEAD -H "X-Requested-With: XMLHttpRequest" "$LANDING_URL" 2>&1)
CONTINUE_URL=$(echo "$HANDSHAKE" | grep -i "Continue-Url" | awk '{print $2}' | tr -d '\\r')

if [ -z "$CONTINUE_URL" ]; then
    echo "Failed to extract Continue-Url. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracted Continue-Url: $CONTINUE_URL" | tee -a "$LOG_FILE"
echo "Constructing final grant request..." | tee -a "$LOG_FILE"

# Dynamic construction of grant URL based on provided HTML structure
BASE_PATH=$(echo "$LANDING_URL" | sed 's/splash\/?.*//')
GRANT_URL="${BASE_PATH}grant?continue_url=$CONTINUE_URL"

echo "Requesting Grant: $GRANT_URL" | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "$GRANT_URL"

echo "Verifying connectivity..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in!" && exit 0 || echo "Login failed or no internet." && exit 1
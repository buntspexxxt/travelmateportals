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

echo "Detecting portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_INFO=$(curl -v -A "$USER_AGENT" -L "http://neverssl.com" 2>&1)
LANDING_URL=$(echo "$REDIRECT_INFO" | sed -n 's/.*Location: //p' | tr -d '\r' | head -n 1)
echo "Landing URL: $LANDING_URL" | tee -a "$LOG_FILE"

echo "Fetching splash page to extract session and path..." | tee -a "$LOG_FILE"
PAGE_HTML=$(curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "$LANDING_URL")

echo "Extracting grant URL from JavaScript logic..." | tee -a "$LOG_FILE"
GRANT_URL=$(echo "$PAGE_HTML" | sed -n 's/.*url = '\''\([^'\']*\)'\'';.*/\1/p' | head -n 1 | sed 's/CONTINUE_URL_PLACEHOLDER/https:\/\/www.obi.de/')

if [ -z "$GRANT_URL" ]; then
    echo "Failed to extract GRANT_URL. Searching for alternative..." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Performing authorization request to: $GRANT_URL" | tee -a "$LOG_FILE"
AUTH_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt -X HEAD "$GRANT_URL")
echo "HTTP Response Status: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in!" && exit 0 || echo "Login failed or no internet." && exit 1
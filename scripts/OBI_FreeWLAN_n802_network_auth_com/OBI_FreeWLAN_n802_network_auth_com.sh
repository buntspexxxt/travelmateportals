#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting multi-stage login script..." | tee -a "$LOG_FILE"

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

echo "Fetching initial landing page..." | tee -a "$LOG_FILE"
# Using -v to see headers, capturing response
REDIRECT_INFO=$(curl -k -v -A "$USER_AGENT" -L "http://neverssl.com" 2>&1)
LANDING_URL=$(echo "$REDIRECT_INFO" | sed -n 's/.*Location: //p' | tr -d '\r' | head -n 1)
echo "Landing URL: $LANDING_URL" | tee -a "$LOG_FILE"

echo "Fetching splash page to acquire session cookies..." | tee -a "$LOG_FILE"
PAGE_HTML=$(curl -k -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "$LANDING_URL")

echo "Executing AJAX handshake to get Continue-Url..." | tee -a "$LOG_FILE"
# Based on portal JS, we need to perform a HEAD request to trigger the header discovery
HANDSHAKE=$(curl -k -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt -X HEAD -H "X-Requested-With: XMLHttpRequest" "$LANDING_URL" 2>&1)
CONTINUE_URL=$(echo "$HANDSHAKE" | sed -n 's/.*Continue-Url: //p' | tr -d '\r')

if [ -z "$CONTINUE_URL" ]; then
    echo "Failed to extract Continue-Url from headers. Falling back to default." | tee -a "$LOG_FILE"
    CONTINUE_URL="https://www.obi.de"
fi
echo "Continue URL target: $CONTINUE_URL" | tee -a "$LOG_FILE"

echo "Extracting grant link from HTML..." | tee -a "$LOG_FILE"
# Extraction of the specific grant link path found in the provided HTML source
GRANT_PATH=$(echo "$PAGE_HTML" | sed -n 's/.*href="\([^"]*grant?continue_url=[^"]*\)".*/\1/p' | head -n 1 | sed 's/&amp;/\&/g')

if [ -z "$GRANT_PATH" ]; then
    echo "Error: Could not find grant link in HTML." | tee -a "$LOG_FILE"
    exit 1
fi

# Replacing placeholder if necessary
FINAL_GRANT_URL=$(echo "$GRANT_PATH" | sed "s/CONTINUE_URL_PLACEHOLDER/$CONTINUE_URL/g")

echo "Submitting grant request to: $FINAL_GRANT_URL" | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "$FINAL_GRANT_URL"

echo "Verifying connectivity..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in!" && exit 0 || echo "Login failed or no internet." && exit 1
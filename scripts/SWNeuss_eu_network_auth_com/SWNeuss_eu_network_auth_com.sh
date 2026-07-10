#!/bin/bash
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE="/tmp/portal_cookies.txt"

echo "Starting login script..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

CHECK_URL="http://neverssl.com"
echo "Detecting portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -m 15 -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%{url_effective}" -o /dev/null "$CHECK_URL" | tr -d '\015')

if [[ "$REDIRECT_URL" == "$CHECK_URL" ]]; then
    echo "No redirect found, already connected." | tee -a "$LOG_FILE"
    exit 0
fi

echo "Landing URL detected: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Downloading portal page and capturing cookies..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -m 15 -k -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "$REDIRECT_URL")

# The HTML uses a direct link to /grant with a continue_url parameter. Extract the base URL dynamically.
BASE_URL=$(echo "$REDIRECT_URL" | cut -d'?' -f1)
# Replace the final component if it's not 'grant'
GRANT_URL=$(echo "$BASE_URL" | sed 's/\/[^\/]*$/\/grant/')

echo "Submitting clickthrough grant request to $GRANT_URL..." | tee -a "$LOG_FILE"
# The portal expects a direct navigation to the grant URL to accept terms
RESPONSE=$(curl -m 15 -k -L -v -b "$COOKIE_FILE" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "$GRANT_URL?continue_url=http://neverssl.com" 2>&1)

echo "HTTP Response captured." | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
echo "Starting login script..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

CHECK_URL="http://neverssl.com"
echo "Detecting portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%{url_effective}" -o /dev/null -s "$CHECK_URL" | tr -d '\015')

if [[ "$REDIRECT_URL" == "$CHECK_URL" ]]; then
    echo "No redirect detected. Already online." | tee -a "$LOG_FILE"
    exit 0
fi

echo "Redirect detected to: $REDIRECT_URL" | tee -a "$LOG_FILE"
BASE_URL=$(echo "$REDIRECT_URL" | cut -d'?' -f1)
QUERY_STRING=$(echo "$REDIRECT_URL" | grep -o '\?.*' | cut -c 2-)

echo "Fetching portal HTML to initialize session..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -k -L -A "Mozilla/5.0" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$REDIRECT_URL")

echo "Requesting Grant URL via HEAD to obtain Continue-Url header..." | tee -a "$LOG_FILE"
CURL_OUT=$(curl -k -I -A "Mozilla/5.0" -H "X-Requested-With: XMLHttpRequest" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$BASE_URL?$QUERY_STRING" 2>&1)
CONTINUE_URL=$(echo "$CURL_OUT" | grep -i "Continue-Url:" | sed 's/.*Continue-Url: \([^\r]*\).*/\1/' | tr -d '\015')

if [ -z "$CONTINUE_URL" ]; then
    echo "Failed to extract Continue-Url. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi

FINAL_URL="$BASE_URL/grant?continue_url=$CONTINUE_URL"
echo "Submitting final authentication: $FINAL_URL" | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "Mozilla/5.0" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$FINAL_URL" 2>&1)

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
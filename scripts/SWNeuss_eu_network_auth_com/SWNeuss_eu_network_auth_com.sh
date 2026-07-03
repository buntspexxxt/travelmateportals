#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." | tee -a "$LOG_FILE"

# Wait for DHCP
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# Detect portal redirect
CHECK_URL="http://neverssl.com"
echo "Checking connectivity to detect redirect..." | tee -a "$LOG_FILE"
REDIRECT_RESPONSE=$(curl -v -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "$CHECK_URL" 2>&1)
LANDING_URL=$(echo "$REDIRECT_RESPONSE" | grep -i "Location:" | sed -n 's/.*Location: //p' | tr -d '\r')

if [ -z "$LANDING_URL" ]; then
    echo "No redirect found. Already connected?" | tee -a "$LOG_FILE"
    exit 0
fi

echo "Landing URL: $LANDING_URL" | tee -a "$LOG_FILE"

# Extract base path and query parameters
BASE_URL=$(echo "$LANDING_URL" | cut -d'?' -f1)
QUERY_PARAMS=$(echo "$LANDING_URL" | grep -o '\?.*')
GRANT_URL=$(echo "$BASE_URL" | sed 's/\/$/grant/')

echo "Executing AJAX grant request to extract Continue-Url..." | tee -a "$LOG_FILE"
# We use the HEAD request logic from the HTML source to fetch the Continue-Url
CURL_OUT=$(curl -v -I -A "Mozilla/5.0" -H "X-Requested-With: XMLHttpRequest" "$BASE_URL$QUERY_PARAMS" 2>&1)
CONTINUE_URL=$(echo "$CURL_OUT" | grep -i "Continue-Url:" | awk '{print $2}' | tr -d '\r')

echo "Final Grant URL Construction..." | tee -a "$LOG_FILE"
FINAL_GRANT_URL="$GRANT_URL?continue_url=$CONTINUE_URL"

echo "Submitting request to: $FINAL_GRANT_URL" | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -L -A "Mozilla/5.0" "$FINAL_GRANT_URL" 2>&1)
echo "HTTP Response Received." | tee -a "$LOG_FILE"

# Final check
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access verified." | tee -a "$LOG_FILE" || { echo "Failed: Connectivity check failed." | tee -a "$LOG_FILE"; exit 1; }
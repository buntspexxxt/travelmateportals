#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting ALDI SÜD Wi-Fi login process." | tee -a "$LOG_FILE"

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

echo "Fetching initial redirect to identify parameters..." | tee -a "$LOG_FILE"
# Extract initial redirect URL from a standard check
REDIRECT_RESPONSE=$(curl -v -A "$USER_AGENT" -o /dev/null "http://detectportal.firefox.com/success.txt" 2>&1)
LOCATION=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*Location: //p' | tr -d '\r')

if [ -z "$LOCATION" ]; then
    echo "Error: Could not capture redirect location." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Redirect URL captured: $LOCATION" | tee -a "$LOG_FILE"

# Extract base path and query parameters
BASE_URL=$(echo "$LOCATION" | cut -d'?' -f1)
QUERY_STRING=$(echo "$LOCATION" | grep -o '?.*' | cut -c 2-)
echo "Extracted Base: $BASE_URL" | tee -a "$LOG_FILE"

echo "Requesting grant endpoint..." | tee -a "$LOG_FILE"
# The portal logic uses a HEAD request to extract the 'Continue-Url' header, then calls the grant URL
# Construct the grant URL dynamically from base path
GRANT_URL="${BASE_URL}grant?$QUERY_STRING"
echo "Targeting Grant URL: $GRANT_URL" | tee -a "$LOG_FILE"

# Perform the final auth POST/GET request
RESPONSE=$(curl -v -A "$USER_AGENT" -H "X-Requested-With: XMLHttpRequest" -X GET "$GRANT_URL")
echo "HTTP Response Received: $RESPONSE" | tee -a "$LOG_FILE"

echo "Running connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access verified." || { echo "Failure: Connectivity check failed." && exit 1; }
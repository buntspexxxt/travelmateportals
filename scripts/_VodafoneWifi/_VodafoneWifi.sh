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

echo "Fetching captive portal redirect URL..." | tee -a "$LOG_FILE"
# Extracting redirect location using curl to connectivity check
REDIRECT_URL=$(curl -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" http://connectivitycheck.gstatic.com/generate_204 2>&1 | grep -i "Location:" | awk '{print $2}' | tr -d '\r')

if [ -z "$REDIRECT_URL" ]; then
    echo "Failed to find redirect URL. Manual intervention might be needed." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Got Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Downloading portal page to extract form fields..." | tee -a "$LOG_FILE"
curl -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "$REDIRECT_URL" -o portal.html

echo "Extracting hidden form fields from HTML..."
# We target the first form which corresponds to 'Easy Login'
FORM_DATA=$(grep -oP 'name="\K[^"]+(?=" value="[^"]*")' portal.html | xargs -I {} sh -c 'echo -n "{}=$(grep -oP "name="$1" value="\K[^"]+" portal.html | head -1)&")' _ {} | sed 's/&$//')

echo "Submitting login form..." | tee -a "$LOG_FILE"
# Using -c/-b to handle session cookies as requested
RESPONSE=$(curl -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -c /tmp/c.txt -b /tmp/c.txt -d "$FORM_DATA" -X POST "$REDIRECT_URL")
echo "HTTP Response Received: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." | tee -a "$LOG_FILE" || { echo "Failed: Connectivity check failed." | tee -a "$LOG_FILE"; exit 1; }
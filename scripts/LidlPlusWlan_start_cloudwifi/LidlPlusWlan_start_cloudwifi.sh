#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." > "$LOG_FILE"

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

echo "Fetching portal landing page to extract redirect URL and hidden fields..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -L -c /tmp/cookies.txt "http://detectportal.firefox.com/success.txt" 2>&1)
echo "HTTP Response captured." | tee -a "$LOG_FILE"

# Extract the URL that we are currently on (the portal page)
EFFECTIVE_URL=$(echo "$RESPONSE" | grep -oE 'Location: https://start.cloudwifi.de/[^ ]+' | tail -n1 | cut -d' ' -f2 | tr -d '\r')
[ -z "$EFFECTIVE_URL" ] && EFFECTIVE_URL="https://start.cloudwifi.de/"

echo "Downloading portal HTML to parse hidden form inputs..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt "$EFFECTIVE_URL")

echo "Extracting form action and hidden fields..." | tee -a "$LOG_FILE"
# Extracting the form action URL from the first login form
ACTION_URL=$(echo "$HTML_CONTENT" | grep -oP 'action="\K[^"]+' | head -n 1 | sed 's/&amp;/\&/g')

# Build post data by extracting all hidden inputs from the first form (FX_loginform_0)
FORM_DATA=$(echo "$HTML_CONTENT" | sed -n '/<form name="FX_loginform_0"/,/</form>/p' | grep -oP '<input type="hidden" name="\K[^"]+value="[^"]*"' | sed 's/" value="/=/' | tr '
' '&' | sed 's/&$//')

echo "Submitting login form..." | tee -a "$LOG_FILE"
POST_RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -X POST -d "$FORM_DATA" "$ACTION_URL" 2>&1)
echo "Login submission response: $POST_RESPONSE" | tee -a "$LOG_FILE"

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >> "$LOG_FILE" 2>&1 && { echo "Login Successful." | tee -a "$LOG_FILE"; exit 0; } || { echo "Login failed or no internet." | tee -a "$LOG_FILE"; exit 1; }
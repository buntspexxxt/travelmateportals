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

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
# Extract initial redirect from the captive portal landing page
REDIRECT_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt "http://detectportal.firefox.com/success.txt" 2>&1)
LOCATION_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*Location: //p' | tr -d '\r' | head -n 1)

if [ -z "$LOCATION_URL" ]; then 
    echo "Failed to get redirect URL. Trying alternative landing..." | tee -a "$LOG_FILE"
    LOCATION_URL="https://start.cloudwifi.de/"
fi

echo "Downloading portal HTML from $LOCATION_URL..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -L "$LOCATION_URL")

echo "Extracting hidden form fields from FX_loginform_0..." | tee -a "$LOG_FILE"
# Get the base action URL (the form submits to itself)
ACTION_URL=$(echo "$HTML_CONTENT" | grep -oP 'name="FX_loginform_0"[^>]*action="\K[^"]+')

# Extract all hidden inputs dynamically
FORM_DATA=$(echo "$HTML_CONTENT" | sed -n '/name="FX_loginform_0"/,/\/<form>/p' | grep -oP '<input type="hidden" name="\K[^"]+" value="[^"]*"' | sed 's/" value="/=/' | tr '
' '&' | sed 's/&$//')

echo "Submitting Easy Login..." | tee -a "$LOG_FILE"
POST_RESULT=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -X POST -d "$FORM_DATA" "$ACTION_URL" 2>&1)
echo "HTTP POST Result: $POST_RESULT" | tee -a "$LOG_FILE"

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
for i in {1..5}; do
    ping -c 3 8.8.8.8 >/dev/null 2>&1 && { echo "Connection established." | tee -a "$LOG_FILE"; exit 0; } || sleep 2
done
echo "Login failed." | tee -a "$LOG_FILE"
exit 1
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
# Get the initial redirect and save headers/cookies
curl -v -A "$USER_AGENT" -L -c /tmp/cookies.txt "http://detectportal.firefox.com/success.txt" -o /dev/null 2> /tmp/curl_debug.txt

# Extract the URL from headers if not found, use default
EFFECTIVE_URL=$(grep -oP 'Location: \Khttps://start.cloudwifi.de/\?res=[^ ]+' /tmp/curl_debug.txt | tail -n1 | tr -d '\r')
[ -z "$EFFECTIVE_URL" ] && EFFECTIVE_URL="https://start.cloudwifi.de/"

echo "Downloading portal page from: $EFFECTIVE_URL" | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -L "$EFFECTIVE_URL")

echo "Parsing form data for 'Easy Login'..." | tee -a "$LOG_FILE"
# We target the form with ID starting with underscore (FX_loginform_0 is the Easy Login form)
# We dynamically extract all inputs to ensure all hidden tokens are included
FORM_DATA=$(echo "$HTML_CONTENT" | sed -n '/<form name="FX_loginform_0"/,/<\/form>/p' | grep -oP '<input type="hidden" name="\K[^"]+" value="[^"]*"' | sed 's/" value="/=/' | tr '
' '&' | sed 's/&$//')

ACTION_URL=$(echo "$HTML_CONTENT" | grep -oP '<form name="FX_loginform_0"[^>]*action="\K[^"]+' | head -n 1 | sed 's/&amp;/\&/g')

echo "Submitting form to $ACTION_URL..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -X POST -d "$FORM_DATA" "$ACTION_URL" >> "$LOG_FILE" 2>&1

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >> "$LOG_FILE" 2>&1 && { echo "Login Successful." | tee -a "$LOG_FILE"; exit 0; } || { echo "Login failed." | tee -a "$LOG_FILE"; exit 1; }
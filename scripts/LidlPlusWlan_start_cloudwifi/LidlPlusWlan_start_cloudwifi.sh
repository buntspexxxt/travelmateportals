#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." > "$LOG_FILE"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found!" | tee -a "$LOG_FILE"; sleep 6; break; fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
# Capture initial redirect and cookies
REDIRECT_URL=$(curl -v -A "$USER_AGENT" -L -c /tmp/cookies.txt "http://detectportal.firefox.com/success.txt" 2>&1 | grep -oP 'Location: \Khttps://start.cloudwifi.de/\?res=[^ ]+' | tail -n1 | tr -d '\\r')

if [ -z "$REDIRECT_URL" ]; then echo "Failed to get redirect URL" | tee -a "$LOG_FILE"; exit 1; fi

echo "Downloading landing page..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -L "$REDIRECT_URL")

echo "Extracting hidden inputs from Easy Login form..." | tee -a "$LOG_FILE"
# Extract form action and inputs
ACTION_URL=$(echo "$HTML_CONTENT" | grep -oP 'name="FX_loginform_0"[^>]*action="[^"]+' | head -n 1 | sed 's/.*action="//')
FORM_DATA=$(echo "$HTML_CONTENT" | sed -n '/name="FX_loginform_0"/,/\/<form>/p' | grep -oP '<input type="hidden" name="\K[^"]+" value="([^"]*)' | sed 's/" value="/=/' | tr '\
' '&' | sed 's/&$//')

echo "Submitting form to $ACTION_URL..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -X POST -d "$FORM_DATA" "$ACTION_URL" >> "$LOG_FILE" 2>&1

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >> "$LOG_FILE" 2>&1 && { echo "Connection established." | tee -a "$LOG_FILE"; exit 0; } || { echo "Login failed." | tee -a "$LOG_FILE"; exit 1; }
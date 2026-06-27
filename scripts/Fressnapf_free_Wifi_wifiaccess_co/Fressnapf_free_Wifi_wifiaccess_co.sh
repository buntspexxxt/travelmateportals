#!/bin/bash
LOG_FILE="/tmp/portal_log.txt"
COOKIE_FILE="/tmp/portal_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Initializing session..." | tee -a "$LOG_FILE"
# Fetch main page to establish session and get API host
RESPONSE=$(curl -A "$USER_AGENT" -c "$COOKIE_FILE" -v "https://wifiaccess.co/103/portal/" 2>&1)
echo "HTTP Response Received." | tee -a "$LOG_FILE"

API_URL="https://wifiaccess.co/portal_api.php"
echo "Calling API Init..." | tee -a "$LOG_FILE"

# Perform initial POST to the API to register the connection
# The portal requires action=init to receive the configuration payload
RESULT=$(curl -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -v -d "action=init" "$API_URL" 2>&1)
echo "API Init complete." | tee -a "$LOG_FILE"

# The portal logic typically requires a 'secure_pwd' (often a generic token or empty) 
# or policy acceptance. We attempt to send a standard connect action.
# Captive portals of this type (Ucopia) usually check policy_accept=true

echo "Submitting connection request..." | tee -a "$LOG_FILE"
RESULT=$(curl -A "$USER_AGENT" -b "$COOKIE_FILE" -v -d "action=authenticate&policy_accept=true&secure_pwd=" "$API_URL" 2>&1)
echo "Auth Result: $RESULT" | tee -a "$LOG_FILE"

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connected!" && exit 0 || exit 1
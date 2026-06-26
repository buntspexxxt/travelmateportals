#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login process for RRX_Hotspot_portal_iob" | tee -a "$LOG_FILE"

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

echo "Fetching redirect URL to extract challenge parameters..." | tee -a "$LOG_FILE"
# We use a known connectivity check URL to trigger the portal redirect
REDIRECT_OUTPUT=$(curl -v -L -A "$USER_AGENT" -o /dev/null -w "%{url_effective}" http://detectportal.firefox.com/success.txt 2>&1)

# Extract the login URL from the redirect parameters
LOGIN_URL=$(echo "$REDIRECT_OUTPUT" | grep -oP 'http[s]?://www.hotsplots.de/auth/login.php[^ ]*')

if [ -z "$LOGIN_URL" ]; then
    echo "Failed to extract login URL from redirect." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Login URL identified: $LOGIN_URL" | tee -a "$LOG_FILE"

echo "Submitting login request to Hotsplots..." | tee -a "$LOG_FILE"
# This portal is a CoovaChilli/Hotsplots system. A simple POST to the redirect URL with 'accept=Accept' usually works.
RESPONSE=$(curl -v -A "$USER_AGENT" -X POST "$LOGIN_URL" -d "accept=Accept&button=Login" 2>&1)

echo "Response received. Verifying connectivity..." | tee -a "$LOG_FILE"
sleep 2
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in!" | tee -a "$LOG_FILE" || { echo "Login failed or no internet access." | tee -a "$LOG_FILE"; exit 1; }
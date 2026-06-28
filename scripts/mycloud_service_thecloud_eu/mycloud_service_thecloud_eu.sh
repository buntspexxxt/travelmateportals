#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE="/tmp/portal_cookies.txt"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching initial landing page..." | tee -a "$LOG_FILE"
PAGE_CONTENT=$(curl -v -A "$UA" -c "$COOKIE_FILE" -L "https://service.thecloud.eu/service-platform/home")

echo "Extracting form action and hidden fields..." | tee -a "$LOG_FILE"
FORM_ACTION="https://service.thecloud.eu/service-platform/macauthlogin/v5/registration"

# The portal requires a POST to the registration endpoint. We simulate the 'Continue' button press.
# Based on the HTML, there are no specific hidden input fields like CSRF tokens listed in the form tag,
# but we perform a POST with empty body as this is a 'one-click' portal.
echo "Submitting registration form..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -o /dev/null -w "%{http_code}" -X POST "$FORM_ACTION")

echo "HTTP Response from registration: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 > /dev/null && echo "Login successful and internet is reachable." | tee -a "$LOG_FILE" || { echo "Login failed or no internet." | tee -a "$LOG_FILE"; exit 1; }
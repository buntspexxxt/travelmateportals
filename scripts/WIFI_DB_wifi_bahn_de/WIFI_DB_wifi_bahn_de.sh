#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies.txt"

echo "Starting login process for WIFI_DB_wifi_bahn_de" | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching initial landing page to obtain session cookies..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L "https://service.thecloud.eu/service-platform/macauthlogin/v5" -o /tmp/login_page.html

echo "Extracting hidden form inputs for authentication..." | tee -a "$LOG_FILE"
# The portal uses a form action to /service-platform/macauthlogin/v5/registration
# We assume common fields are embedded in the response or handled by session

echo "Submitting terms and conditions..." | tee -a "$LOG_FILE"
# Based on the provided HTML, we need to POST to the registration endpoint
# The registration form is simple: it posts to /service-platform/macauthlogin/v5/registration
RESPONSE_CODE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -X POST "https://service.thecloud.eu/service-platform/macauthlogin/v5/registration" -w "%{http_code}" -o /tmp/login_result.html)

echo "Login HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Finalizing connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet reached." | tee -a "$LOG_FILE" && exit 0 || echo "Failed: Connectivity not established." | tee -a "$LOG_FILE" && exit 1
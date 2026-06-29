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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/portal_cookies.txt"

echo "Accessing landing page to retrieve session..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L "https://public.hotspot.koeln/cp/guqs6n9d")

echo "Submitting form to login..." | tee -a "$LOG_FILE"
# The portal uses a simple POST request with a checkbox confirmation (required) and a fixed hidden field.
# We are simulating the 'oneclick' login action.
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -d "customControlValidation1=on" \
  -d "login=oneclick" \
  "https://public.hotspot.koeln/login" | tee -a "$LOG_FILE"

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Connected to Internet." | tee -a "$LOG_FILE" && exit 0 || { echo "Error: Failed to connect." | tee -a "$LOG_FILE"; exit 1; }
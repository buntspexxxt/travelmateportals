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

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -A "$USER_AGENT" -v -L -c "$COOKIE_FILE" "http://neverssl.com" 2>&1 | grep "Location:" | tail -n1 | awk '{print $2}' | tr -d '\r')
echo "Captured Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

BASE_URL=$(echo "$REDIRECT_URL" | cut -d'?' -f1)
echo "Base Portal URL: $BASE_URL" | tee -a "$LOG_FILE"

echo "Downloading portal page to extract hidden fields..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "$REDIRECT_URL")
echo "HTML downloaded." | tee -a "$LOG_FILE"

echo "Extracting hidden inputs..." | tee -a "$LOG_FILE"
AP_MAC=$(echo "$HTML_CONTENT" | grep -o 'name="ap_mac" value="[^"]*"' | cut -d'"' -f4)
CLIENT_MAC=$(echo "$HTML_CONTENT" | grep -o 'name="client_mac" value="[^"]*"' | cut -d'"' -f4)
WLAN_ID=$(echo "$HTML_CONTENT" | grep -o 'name="wlan_id" value="[^"]*"' | cut -d'"' -f4)
URL_VAL=$(echo "$HTML_CONTENT" | grep -o 'name="url" value="[^"]*"' | cut -d'"' -f4)

POST_DATA="ap_mac=$AP_MAC&client_mac=$CLIENT_MAC&wlan_id=$WLAN_ID&url=${URL_VAL//&/%26}&tos=true&auth_method=passphrase"

echo "Submitting POST request to $BASE_URL..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -v -X POST -d "$POST_DATA" "$BASE_URL")
echo "POST Request sent." | tee -a "$LOG_FILE"

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." | tee -a "$LOG_FILE" && exit 0 || { echo "Error: No internet access."; exit 1; }
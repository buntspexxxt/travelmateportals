#!/bin/bash

LOG_FILE="/tmp/captive_portal_log.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting captive portal script for SSID: Fressnapf_free_Wifi_192_168_8_1"

# Wait for DHCP and gateway assignment
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default;
    then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# User Agent to mimic a modern browser
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Check initial connectivity and detect portal
echo "Checking initial connectivity and detecting captive portal..." | tee -a "$LOG_FILE"
DETECT_URL="http://detectportal.firefox.com/success.txt"

# Use curl with -L to follow redirects and -v for verbose output
DETECT_RESPONSE=$(curl -L -v "$DETECT_URL" -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt 2>&1)
DETECT_HTTP_CODE=$(echo "$DETECT_RESPONSE" | grep "HTTP/1.1" | awk '{print $2}' | tail -n 1)

echo "Detection curl output:" >> "$LOG_FILE"
echo "$DETECT_RESPONSE" >> "$LOG_FILE"

if [[ "$DETECT_HTTP_CODE" -ne "200" && "$DETECT_HTTP_CODE" -ne "302" ]]; then
    echo "Error: Failed to detect portal. HTTP code: $DETECT_HTTP_CODE. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

# Extract the effective URL after redirects
echo "Extracting effective URL..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(echo "$DETECT_RESPONSE" | grep -oP "Location: \K.*?(?=
|)" | tail -n 1)
if [[ -z "$EFFECTIVE_URL" ]]; then
    EFFECTIVE_URL=$(echo "$DETECT_RESPONSE" | grep -oP "https?://[^ 
]*" | tail -n 1)
fi

if [[ -z "$EFFECTIVE_URL" ]]; then
    echo "Error: Could not determine effective URL. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Navigate to the effective URL to get the portal page
echo "Navigating to the portal page: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

PORTAL_PAGE_RESPONSE=$(curl -L -v "$EFFECTIVE_URL" -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt 2>&1)
PORTAL_PAGE_HTTP_CODE=$(echo "$PORTAL_PAGE_RESPONSE" | grep "HTTP/1.1" | awk '{print $2}' | tail -n 1)

echo "Portal page curl output:" >> "$LOG_FILE"
echo "$PORTAL_PAGE_RESPONSE" >> "$LOG_FILE"

if [[ "$PORTAL_PAGE_HTTP_CODE" -ne "200" ]]; then
    echo "Error: Failed to fetch portal page. HTTP code: $PORTAL_PAGE_HTTP_CODE. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

# Extract form fields if any - In this case, no form fields are obvious, it seems to be a direct script load
# If there were hidden fields, we would parse them here like:
# HIDE_FIELD_VALUE=$(echo "$PORTAL_PAGE_RESPONSE" | grep -o '<input type="hidden" name="[^"]*" value="[^"]*">' | sed 's/.*name="\([^"]*\)".*value="\([^"]*\)".*/\1=\2/' | paste -sd '&')

# The provided HTML/JS indicates that the app.js is loaded. We'll assume a POST request to the base URL with minimal data might work.
# The most likely scenario for a simple portal is a POST to the current URL or a specific login endpoint.
# Since no explicit form or login fields are present, and the JS is loaded, this implies a SPA which is harder to automate.
# However, the HTML structure is very basic. We will try a POST to the root URL of the detected effective URL.

echo "Attempting to POST to the portal root URL to establish session..." | tee -a "$LOG_FILE"

# Extract base URL for POST request
BASE_URL=$(echo "$EFFECTIVE_URL" | grep -oP "^https?://[^/]*")

# Prepare POST data. Since no fields are identified, we'll send an empty body initially, relying on cookies.
# If this fails, more sophisticated analysis of app.js would be needed.
POST_DATA=""

LOGIN_RESPONSE=$(curl -L -v -X POST "$BASE_URL/" -A "$USER_AGENT" -d "$POST_DATA" -c /tmp/cookies.txt -b /tmp/cookies.txt 2>&1)
LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE" | grep "HTTP/1.1" | awk '{print $2}' | tail -n 1)

echo "Login POST request output:" >> "$LOG_FILE"
echo "$LOGIN_RESPONSE" >> "$LOG_FILE"

if [[ "$LOGIN_HTTP_CODE" -eq "200" || "$LOGIN_HTTP_CODE" -eq "302" ]]; then
    echo "Login successful (HTTP code: $LOGIN_HTTP_CODE)." | tee -a "$LOG_FILE"
else
    echo "Error: Login failed. HTTP code: $LOGIN_HTTP_CODE. Further investigation needed." | tee -a "$LOG_FILE"
    exit 1
fi

# Final connectivity check
echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null

if [ $? -eq 0 ]; then
    echo "Connectivity check successful. Script finished." | tee -a "$LOG_FILE"
    exit 0
else
    echo "Connectivity check failed. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

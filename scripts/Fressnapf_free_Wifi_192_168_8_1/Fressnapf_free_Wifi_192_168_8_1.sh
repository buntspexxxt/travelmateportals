#!/bin/bash

# SSID: Fressnapf_free_Wifi_192_168_8_1
# Script to automate login to the captive portal.

# --- CRITICAL ANALYSIS --- 
# The provided HTML, JavaScript, and previous execution logs indicate that the device has ALREADY BYPASSED the captive portal, or that no captive portal is active for the 'Fressnapf_free_Wifi_192_168_8_1' network.
# The initial request to http://1.1.1.1/ successfully redirects and retrieves the content from https://one.one.one.one/ (Cloudflare's 1.1.1.1 marketing page).
# There are NO login forms, 'accept terms' buttons, hidden input fields, or any other interactive elements in the provided HTML that would constitute a captive portal login mechanism.
# Therefore, this script will not attempt a login, as there is no portal interaction required based on the provided data.
# It will simply perform a connectivity check to confirm internet access.

echo "--- Captive Portal Analysis for SSID: Fressnapf_free_Wifi_192_168_8_1 ---"
echo ""
echo "WARNING: Based on the provided HTML, JS, and logs, your device appears to have already bypassed the captive portal or no portal is active."
echo "The system successfully reached and downloaded content from Cloudflare's 1.1.1.1 website (https://one.one.one.one/)."
echo "There is no login form or interaction required in the provided data."
echo ""
echo "Proceeding with a direct internet connectivity check."

# --- Connectivity Check ---

# Cookie file for curl operations
COOKIE_FILE="/tmp/curl_cookies_$$.txt"

# Step 1: Attempt to reach an external, reliable website (e.g., google.com) to verify internet access.
echo "[STEP 1/1] Attempting to reach google.com to verify internet connectivity..."
CONNECTIVITY_RESPONSE=$(curl -v -L -o /dev/null --write-out "%{http_code}" https://www.google.com 2>&1)
CURL_EXIT_CODE=$?

if [ $CURL_EXIT_CODE -eq 0 ]; then
    echo "HTTP Response for google.com: ${CONNECTIVITY_RESPONSE}"
    echo "Curl command succeeded. Checking status code..."
    # Check if the HTTP status code indicates success (e.g., 2xx or 3xx for redirects followed successfully)
    if [[ "$CONNECTIVITY_RESPONSE" =~ ^(2|3)[0-9]{2}$ ]]; then
        echo "Successfully connected to google.com. Internet access appears to be active."
        rm -f "$COOKIE_FILE"
        exit 0
    else
        echo "Failed to connect to google.com with a successful HTTP status code. Received: ${CONNECTIVITY_RESPONSE}"
        echo "Connectivity check failed. Internet access might still be restricted."
        rm -f "$COOKIE_FILE"
        exit 1
    fi
else
    echo "Curl command failed with exit code $CURL_EXIT_CODE. Internet access is likely not available."
    echo "Curl output:"
    echo "${CONNECTIVITY_RESPONSE}"
    rm -f "$COOKIE_FILE"
    exit 1
fi

# Cleanup cookie file (this line might be redundant if previous exits are hit, but good practice)
rm -f "$COOKIE_FILE"

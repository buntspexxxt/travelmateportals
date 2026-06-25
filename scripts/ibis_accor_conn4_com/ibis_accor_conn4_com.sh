#!/bin/bash

# --- Configuration ---
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/accor_conn4_cookies.txt"
LOG_FILE="/tmp/accor_conn4_login.log"

# Ensure DHCP is ready
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# Clear previous logs and cookie file
> "$LOG_FILE"
echo "--- Starting ibis_accor_conn4_com login script ---" | tee -a "$LOG_FILE"
rm -f "$COOKIE_FILE"

# --- Step 1: Initialize Session ---
echo "STEP 1: Probing portal detection..." | tee -a "$LOG_FILE"
CURL_OUTPUT_STEP1=$(curl -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" "http://detectportal.firefox.com/success.txt" 2>&1)
EFFECTIVE_URL=$(echo "$CURL_OUTPUT_STEP1" | grep -oP '(?<=^< Location: |^< location: ).*' | tail -1 | tr -d '\r')
BASE_DOMAIN=$(echo "$EFFECTIVE_URL" | awk -F'[/:]' '{print $4}')

echo "STEP 2: Fetching Landing Page..." | tee -a "$LOG_FILE"
HTML_RESPONSE=$(curl -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$EFFECTIVE_URL" 2>&1)
SCENE_PLAYER_URI=$(echo "$HTML_RESPONSE" | grep -oP '"scenePlayerUri":"\\K[^"]*' | sed 's/\\\\//g')
SCENE_PLAYER_URL="https://$BASE_DOMAIN$SCENE_PLAYER_URI"

# --- Step 3: Activation ---
# Based on portal structure, we must hit the API to initiate the free 24h session.
echo "STEP 3: POSTing to $SCENE_PLAYER_URL for free 24h access..." | tee -a "$LOG_FILE"
# Using generic form fields identified in Accor/Conn4 portal logic
POST_DATA="action=connect_free&agreement=true"

LOGIN_RESPONSE=$(curl -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "$POST_DATA" "$SCENE_PLAYER_URL" 2>&1)

if echo "$LOGIN_RESPONSE" | grep -q "200"; then
    echo "Login Request Sent. Checking connectivity..." | tee -a "$LOG_FILE"
else
    echo "Warning: POST returned unexpected status. Checking connectivity anyway." | tee -a "$LOG_FILE"
fi

# --- Step 4: Connectivity Check ---
sleep 5
ping -c 3 8.8.8.8 >/dev/null && echo "Connectivity confirmed." || { echo "Connectivity failed."; exit 1; }
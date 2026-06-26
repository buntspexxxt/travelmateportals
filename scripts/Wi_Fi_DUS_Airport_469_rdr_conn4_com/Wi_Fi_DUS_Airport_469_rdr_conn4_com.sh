#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE="/tmp/portal_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting portal login script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# Step 1: Initialize session and get the token page
BASE_URL="https://469.rdr.conn4.com"
echo "Fetching portal index..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /tmp/portal.html "$BASE_URL/" 2>&1 | tee -a "$LOG_FILE"

# Step 2: Extract Token
WBS_TOKEN=$(grep -o '"token":"[^"]*"' /tmp/portal.html | head -1 | sed 's/"token":"//' | sed 's/"//')
if [ -z "$WBS_TOKEN" ]; then
    echo "Error: Could not find WBS Token." | tee -a "$LOG_FILE"
    exit 1
fi

# Step 3: POST token to initialize sequence
echo "Posting WBS Token..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "token=$WBS_TOKEN" "$BASE_URL/wbs/de/roaming/return/" 2>&1 | tee -a "$LOG_FILE"

# Step 4: Handle the scene selection (Free vs Paid)
# Based on the requirement to select the 'free' option
# Typically portals with 'scenes' use an API to trigger the free plan
echo "Requesting free internet access..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$BASE_URL/api/v1/scene/trigger" -d "action=free" 2>&1 | tee -a "$LOG_FILE"

# Connectivity check
echo "Performing connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connectivity confirmed!" | tee -a "$LOG_FILE" && exit 0 || exit 1
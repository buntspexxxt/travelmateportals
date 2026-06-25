#!/bin/bash

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/rrx_hotspot_cookies.txt"

echo "Starting RRX_Hotspot_portal_iob login script..."

# Step 1: Trigger initial redirect
echo "Accessing landing page to identify session..."
curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" "http://portal.iob.de/" > /dev/null 2>&1

# Step 2: Hit the prelogin endpoint which triggers the Hotsplots redirect
echo "Triggering /prelogin..."
PRELOGIN_RESPONSE=$(curl -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "http://192.168.44.1/prelogin" 2>&1)

# Extract Hotsplots Auth URL from the redirect
AUTH_URL=$(echo "$PRELOGIN_RESPONSE" | grep -E '^< Location: ' | tail -n 1 | awk '{print $2}' | tr -d '\r')

if [ -z "$AUTH_URL" ]; then
    echo "ERROR: Could not extract Hotsplots Auth URL. Checking if already logged in..."
else
    echo "Redirecting to Hotsplots auth: $AUTH_URL"
    # Extract params to build POST
    QUERY=$(echo "$AUTH_URL" | cut -d '?' -f 2)
    
    echo "Submitting Hotsplots POST request..."
    curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST -d "$QUERY&login=1" "$AUTH_URL" > /dev/null 2>&1
fi

# Final connectivity check
echo "Checking connectivity..."
ping -c 3 8.8.8.8 >/dev/null && echo "SUCCESS: Internet online!" || { echo "FAILURE: No internet."; exit 1; }
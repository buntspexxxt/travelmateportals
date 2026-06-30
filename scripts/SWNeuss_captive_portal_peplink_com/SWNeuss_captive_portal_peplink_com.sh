#!/bin/bash
echo "Starting Captive Portal Login Script..."

# 1. Wait for Network
echo "Waiting for DHCP (IP & Gateway)..."
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful."
        sleep 6
        break
    fi
    sleep 1
done

# 2. Define Variables
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
# Detect landing redirect from captive portal check
echo "Fetching initial redirect..."
REDIRECT_URL=$(curl -v -A "$USER_AGENT" -L -s -o /dev/null -w "%{url_effective}" http://detectportal.firefox.com/success.txt)
echo "Redirect URL: $REDIRECT_URL"

# 3. Extract query parameters from redirect
QUERY_STRING=$(echo "$REDIRECT_URL" | grep -o '?.*' | cut -c 2-)
echo "Extracted Query String: $QUERY_STRING"

# 4. Attempt to resume session via Peplink API
# The portal logic shows a call to /cp/session/resume
# We dynamically reconstruct parameters based on the landing URL
BASE_API="https://guest7.ic.peplink.com/cp/session/resume"
echo "Checking session resume API..."

# Extracting parameters into a format compatible with curl POST
# Using the query string as post data for the resume API
RESPONSE=$(curl -v -A "$USER_AGENT" -X POST "$BASE_API" -d "$QUERY_STRING" -H "Content-Type: application/x-www-form-urlencoded")
echo "API Response: $RESPONSE"

# 5. Connect if session not active
if echo "$RESPONSE" | grep -q "logout"; then
    echo "Session requires login. Sending login command..."
    curl -v -A "$USER_AGENT" "https://guest7.ic.peplink.com/cp/login?$QUERY_STRING&command=login"
else
    echo "Session appears active or already logged in."
fi

# 6. Final Connectivity Check
echo "Performing final connectivity check..."
ping -c 3 8.8.8.8 >/dev/null && { echo "Connectivity confirmed!" ; exit 0; } || { echo "Connectivity failed." ; exit 1; }
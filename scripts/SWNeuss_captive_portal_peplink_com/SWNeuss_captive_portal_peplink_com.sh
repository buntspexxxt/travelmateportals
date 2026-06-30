#!/bin/bash
echo "Starting ALDI SÜD Portal Login Script..."

# 1. Wait for Network
echo "Waiting for DHCP..."
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found."; sleep 6; break; fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/wifi_cookies.txt"

# 2. Get initial redirect
echo "Fetching initial redirect..."
REDIRECT_URL=$(curl -v -A "$USER_AGENT" -L -c "$COOKIE_FILE" -s -o /dev/null -w "%{url_effective}" http://connectivitycheck.gstatic.com/generate_204)
echo "Redirect URL: $REDIRECT_URL"

# 3. Extract the grant URL base and perform the handshake
# The portal uses an XHR HEAD request to obtain the 'Continue-Url' header before navigation
echo "Fetching session headers..."
HEADER_RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -I -X HEAD "$REDIRECT_URL")
CONTINUE_URL=$(echo "$HEADER_RESPONSE" | sed -n 's/Continue-Url: //p' | tr -d '\\r')

# 4. Perform the grant request
# Based on the JS analysis, the button triggers a visit to /grant?continue_url=...
# We reconstruct the URL from the redirect path
GRANT_URL=$(echo "$REDIRECT_URL" | sed 's/\/$/\/grant/')
FINAL_GRANT_URL="${GRANT_URL}?continue_url=${CONTINUE_URL}"

echo "Performing final login grant..."
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" "$FINAL_GRANT_URL"

# 5. Connectivity check
echo "Checking internet..."
ping -c 3 8.8.8.8 >/dev/null && { echo "Success!"; exit 0; } || { echo "Failed."; exit 1; }
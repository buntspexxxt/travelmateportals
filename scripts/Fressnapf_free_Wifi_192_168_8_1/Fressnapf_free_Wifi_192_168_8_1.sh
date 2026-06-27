#!/bin/bash
LOG_FILE="/tmp/captive_portal_login.log"
exec > >(tee -a "$LOG_FILE") 2>&1

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Wait for DHCP
echo "Waiting for DHCP (IP & Gateway)..."
for i in {1..20}; do
    if ip route | grep -q default;
    then
        echo "Gateway found! DHCP successful."
        sleep 6
        break
    fi
    sleep 1
done

echo "DHCP wait finished."

echo "Attempting to detect captive portal."
# Detect portal using Firefox checker (modified to capture effective URL)
DETECT_URL="http://detectportal.firefox.com/success.txt"
DETECT_RESPONSE=$(curl -L -A "$USER_AGENT" -w "%{http_code}" -o /tmp/detect_response.html "$DETECT_URL")
DETECT_HTTP_CODE=$?

if [ $DETECT_HTTP_CODE -ne 0 ]; then
    echo "Error during portal detection. Curl exited with code $DETECT_HTTP_CODE."
    exit 1
elif [ "$DETECT_RESPONSE" -ne 200 ]; then
    echo "Portal detection failed. HTTP status code: $DETECT_RESPONSE"
    exit 1
fi

EFFECTIVE_URL=$(curl -L -A "$USER_AGENT" -I "$DETECT_URL" 2>/dev/null | grep -i '^Location:' | awk '{print $2}' | tr -d '\r')
echo "Effective URL after detection: $EFFECTIVE_URL"

# If the effective URL redirects to a different portal page, we need to get that page
if [[ "$EFFECTIVE_URL" == http* ]]; then
    echo "Fetching the actual portal page from $EFFECTIVE_URL"
 PORTAL_PAGE_URL="$EFFECTIVE_URL"
else
    echo "No redirect found after detection, assuming the initial URL is the portal page."
    PORTAL_PAGE_URL="https://192.168.8.1/"
fi

# The provided HTML and JS are for an 'Admin Panel' and suggest client-side rendering.
# The JS file 'app.df46d5a0.js' is likely to handle authentication logic, token generation, 
# or complex form submissions that cannot be easily replicated with static curl commands.
# Without a clear HTML form or a readily identifiable API endpoint in the JS that can be called with curl,
# this portal is considered complex.

echo "This captive portal appears to rely on JavaScript for login."
echo "The provided HTML and JS do not contain a simple HTML form or obvious API endpoints for direct login."
echo "Automating this with curl is not feasible without reverse-engineering the JavaScript logic."

# Exit with failure as this requires complex JS interaction
exit 1

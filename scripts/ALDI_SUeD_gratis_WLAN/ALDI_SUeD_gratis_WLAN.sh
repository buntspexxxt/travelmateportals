
# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# LOG_FILE variable definition
LOG_FILE="/tmp/captive_portal.log"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# ALDI Süd gratis WLAN usually uses a redirect to a splash page.
# Since the logs show that the connection is already active (Google 204 and Firefox success.txt returned normal responses),
# we will first check if we already have internet access.

echo "Checking current connection state..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Already connected to the Internet!"
    exit 0
fi

# If we are not connected, let's trigger the redirect
echo "Attempting to trigger captive portal redirect..."
COOKIE_FILE=$(mktemp)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Get the redirect URL
REDIRECT_RESP=$(curl -m 15 -k -v -L -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -w "%{url_effective}" -o /tmp/portal_page.html "http://neverssl.com/")
echo "Effective landing URL: $REDIRECT_RESP"

# In many Aldi Süd (and other German supermarkets like Lidl/Edeka) portals, 
# they are operated by providers like Landis, Vodafone, or others. 
# Often, a simple POST or GET with terms acceptance is needed. 
# If we are redirected to a portal, let's extract the form action or use common endpoints.

if [ -f /tmp/portal_page.html ]; then
    echo "Analyzing portal page..."
    # Look for form action
    FORM_ACTION=$(grep -i '<form' /tmp/portal_page.html | sed -n 's/.*action="\([^"]*\)".*/\1/p' | head -n 1)
    echo "Found form action: $FORM_ACTION"
    
    if [ -n "$FORM_ACTION" ]; then
        # Resolve relative action URL
        BASE_URL=$(echo "$REDIRECT_RESP" | sed -n 's/\(https*:\/\/[^\/]*\).*/\1/p')
        if echo "$FORM_ACTION" | grep -q -e "^http"; then
            POST_URL="$FORM_ACTION"
        else
            POST_URL="${BASE_URL}${FORM_ACTION}"
        fi
        
        echo "Submitting terms acceptance to $POST_URL"
        # Extract any hidden fields (like csrf, magic, session, etc.)
        # We build a post string dynamically
        POST_DATA=""
        # Get all input names and values
        # Standard POSIX sed to extract inputs
        # We'll just try to send standard parameters or submit the form as is
        
        # Execute the form submission
        curl -m 15 -k -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" "$POST_URL"
    fi
fi

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
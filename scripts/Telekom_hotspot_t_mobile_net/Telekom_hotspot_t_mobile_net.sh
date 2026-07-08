#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="/tmp/telekom_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting login script for Telekom Hotspot..." | tee -a "$LOG_FILE"

# CRITICAL: Waiting for IP, Gateway, and DNS to be fully assigned
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# Check if already online
echo "Checking if internet connectivity already exists..." | tee -a "$LOG_FILE"
CHECK_CODE_INITIAL=$(curl -k -s -o /dev/null -w "%{\http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE_INITIAL" = "204" ] || [ "$CHECK_CODE_INITIAL" = "200" ]; then
    echo "Already online. Exiting." | tee -a "$LOG_FILE"
    exit 0
fi

# 1. Get the initial redirect page from neverssl.com and capture all redirects
echo "Fetching redirect page from neverssl.com and populating cookies..." | tee -a "$LOG_FILE"
rm -f "$COOKIE_JAR"

# Use -L to follow redirects, -v for verbose output including all Location headers
FIRST_REDIRECT_RESPONSE=$(curl -k -v -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
     --connect-timeout 15      --user-agent "$USER_AGENT" \
     "http://neverssl.com" 2>&1)

if [ ! -f "$COOKIE_JAR" ]; then
    echo "Warning: No cookie jar file created." | tee -a "$LOG_FILE"
fi

# Extract the final effective URL after all redirects
FINAL_LANDING_URL=$(echo "$FIRST_REDIRECT_RESPONSE" | grep -i "< Location:" | tail -n 1 | sed -n "s/^.*Location: //p" | sed 's/\r//g')
if [ -z "$FINAL_LANDING_URL" ]; then
    echo "ERROR: Could not extract final effective URL after redirects." | tee -a "$LOG_FILE"
    echo "Curl Response: $FIRST_REDIRECT_RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi
echo "Final effective URL after redirects: $FINAL_LANDING_URL" | tee -a "$LOG_FILE"

# Capture the original URL that was requested by the client, for the 'OriginatingServer' parameter.
# This is typically found as the 'origurl' parameter in the initial redirect to hotspot.t-mobile.net/wlan/redirect.do
echo "Extracting originating server URL for POST data..." | tee -a "$LOG_FILE"
FIRST_HOTSPOT_REDIRECT=$(echo "$FIRST_REDIRECT_RESPONSE" | grep -i "< Location: .*hotspot.t-mobile.net/wlan/redirect.do" | head -n 1 | sed -n "s/^.*Location: //p" | sed 's/\r//g')
ORIGINATING_SERVER_RAW="http://neverssl.com" # Default fallback
if [ -n "$FIRST_HOTSPOT_REDIRECT" ]; then
    # Decode %3A, %2F, etc. to get the raw URL
    TEMP_ORIG_SERVER=$(echo "$FIRST_HOTSPOT_REDIRECT" | sed -n 's/.*origurl=\([^&]*\).*/\1/p')
    if [ -n "$TEMP_ORIG_SERVER" ]; then
        ORIGINATING_SERVER_RAW=$(echo "$TEMP_ORIG_SERVER" | sed 's/%3A/:/g; s/%2F/\//g; s/%3F/?/g; s/%3D/=/g; s/%26/&/g')
    fi
fi
echo "Extracted OriginatingServer (decoded): $ORIGINATING_SERVER_RAW" | tee -a "$LOG_FILE"

# URL encode it for the POST request body
ORIGINATING_SERVER=$(echo "$ORIGINATING_SERVER_RAW" | sed 's/:/%3A/g; s/\//%2F/g; s/&/%26/g; s/?/%3F/g; s/=/%3D/g')
echo "Encoded OriginatingServer for POST: $ORIGINATING_SERVER" | tee -a "$LOG_FILE"

# 2. Fetch the FINAL_LANDING_URL HTML content to parse for the actual <loginurl>
echo "Fetching the final landing page HTML from: $FINAL_LANDING_URL" | tee -a "$LOG_FILE"
LANDING_PAGE_HTML_RESPONSE=$(curl -k -v -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" --connect-timeout 15 --user-agent "$USER_AGENT" "$FINAL_LANDING_URL" 2>&1)

HTTP_STATUS_LANDING=$(echo "$LANDING_PAGE_HTML_RESPONSE" | grep -i "< HTTP/" | tail -n 1 | awk '{print $3}')
echo "HTTP Status for landing page HTML fetch: $HTTP_STATUS_LANDING" | tee -a "$LOG_FILE"
if [ "$HTTP_STATUS_LANDING" != "200" ]; then
    echo "ERROR: Failed to get 200 OK for landing page. Status: $HTTP_STATUS_LANDING" | tee -a "$LOG_FILE"
    echo "Curl Response: $LANDING_PAGE_HTML_RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi

# Extract the <loginurl> from the HTML, as per the Travelmate script hint.
# This is assumed to be in the LANDING_PAGE_HTML, not the Angular page provided in the prompt.
LOGIN_URL=$(echo "$LANDING_PAGE_HTML_RESPONSE" | sed -n 's/.*<loginurl>\(.*\)<\/loginurl>.*/\1/p' | sed 's/&amp;/&/g' | head -n 1 | sed 's/\r//g')
if [ -z "$LOGIN_URL" ]; then
    echo "ERROR: Could not extract <loginurl> from the landing page HTML. This is critical for Telekom Hotspot login." | tee -a "$LOG_FILE"
    echo "Landing page HTML (partial, where loginurl was sought):" | tee -a "$LOG_FILE"
    echo "$LANDING_PAGE_HTML_RESPONSE" | head -n 20 | tee -a "$LOG_FILE" # Log first 20 lines for debugging
    exit 1
fi
echo "Extracted LOGIN_URL: $LOGIN_URL" | tee -a "$LOG_FILE"

# 3. Perform the actual login POST using the extracted LOGIN_URL
echo "Submitting login POST to: $LOGIN_URL" | tee -a "$LOG_FILE"
# The Referer header is crucial as per the Travelmate script hint, pointing to the general freeLogin endpoint.
LOGIN_REFERER="https://hotspot.t-mobile.net/wlan/rest/freeLogin"
LOGIN_POST_DATA="UserName=&Password=&FNAME=0&button=Login&OriginatingServer=$ORIGINATING_SERVER"

FINAL_LOGIN_RESPONSE=$(curl -k -v -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
     -X POST "$LOGIN_URL" \
     --connect-timeout 15 \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -H "Referer: $LOGIN_REFERER" \
     --user-agent "$USER_AGENT" \
     -d "$LOGIN_POST_DATA" 2>&1)

HTTP_STATUS_LOGIN_POST=$(echo "$FINAL_LOGIN_RESPONSE" | grep -i "< HTTP/" | tail -n 1 | awk '{print $3}')
echo "HTTP Status for login POST: $HTTP_STATUS_LOGIN_POST" | tee -a "$LOG_FILE"
echo "Response from final login POST:" | tee -a "$LOG_FILE"
echo "$FINAL_LOGIN_RESPONSE" | tee -a "$LOG_FILE"

# As per Travelmate script, check for <logoffurl> to confirm success
LOGOFF_URL=$(echo "$FINAL_LOGIN_RESPONSE" | sed -n 's/.*<logoffurl>\(.*\)<\/logoffurl>.*/\1/p' | sed 's/&amp;/&/g' | head -n 1 | sed 's/\r//g')

if [ -n "$LOGOFF_URL" ]; then
    echo "SUCCESS: <logoffurl> found in response, indicating successful login (Logoff URL: $LOGOFF_URL)." | tee -a "$LOG_FILE"
    # Proceed to final internet verification
else
    echo "WARNING: No <logoffurl> found in response. Login might not have been fully successful." | tee -a "$LOG_FILE"
    # Attempting to verify internet connection regardless, as sometimes the response doesn't contain it but access is granted.
fi

# CRITICAL MANDATORY VERIFICATION: Verify real Internet connectivity
echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{\http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    rm -f "$COOKIE_JAR"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    rm -f "$COOKIE_JAR"
    exit 1
fi

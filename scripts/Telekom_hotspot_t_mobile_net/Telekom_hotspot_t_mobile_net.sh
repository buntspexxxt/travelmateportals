#!/bin/bash

# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
POST_RESPONSE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Sane cleanup on exit
trap 'rm -f "$COOKIE_FILE" "$HTML_FILE" "$POST_RESPONSE_FILE"' EXIT

echo "Starting login script for Telekom Hotspot (SSID: Telekom_hotspot_t_mobile_net)..." | tee -a "$LOG_FILE"

# CRITICAL: Waiting for IP, Gateway, and DNS to be fully assigned
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# Check if already online
echo "Checking if internet connectivity already exists..." | tee -a "$LOG_FILE"
CHECK_CODE_INITIAL=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE_INITIAL" = "204" ] || [ "$CHECK_CODE_INITIAL" = "200" ]; then
    echo "Already online. Exiting." | tee -a "$LOG_FILE"
    exit 0
fi

# Step 1: Detect redirect without following it, to locate the captive gateway servlet
echo "Probing http://neverssl.com for captive portal redirection..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -m 15 -k -o /dev/null -w "%{redirect_url}" --connect-timeout 15 -A "$USER_AGENT" "http://neverssl.com" | tr -d '\015')

if [ -z "$REDIRECT_URL" ]; then
    echo "No redirect header found. Accessing the page directly to see if WISPr XML is returned..." | tee -a "$LOG_FILE"
    curl -m 15 -k -c "$COOKIE_FILE" -b "$COOKIE_FILE" --connect-timeout 15 -A "$USER_AGENT" -o "$HTML_FILE" "http://neverssl.com"
else
    echo "Redirect URL detected: $REDIRECT_URL" | tee -a "$LOG_FILE"
    echo "Fetching redirect page to capture the portal XML..." | tee -a "$LOG_FILE"
    curl -m 15 -k -c "$COOKIE_FILE" -b "$COOKIE_FILE" --connect-timeout 15 -A "$USER_AGENT" -o "$HTML_FILE" "$REDIRECT_URL"
fi

# Step 2: Extract the <loginurl> from the WISPr XML/HTML
echo "Extracting <loginurl> from response..." | tee -a "$LOG_FILE"
LOGIN_URL=$(cat "$HTML_FILE" | tr -d '\015' | sed -n 's/.*[Ll][Oo][Gg][Ii][Nn][Uu][Rr][Ll]>[[:space:]]*\([^<]*\)[[:space:]]*<\/[Ll][Oo][Gg][Ii][Nn][Uu][Rr][Ll]>.*/\1/p' | sed 's/&amp;/\&/g' | head -n 1)

if [ -z "$LOGIN_URL" ]; then
    echo "ERROR: Could not extract <loginurl> from the captive portal page." | tee -a "$LOG_FILE"
    echo "Saving HTML output to log for debugging:" | tee -a "$LOG_FILE"
    cat "$HTML_FILE" >> "$LOG_FILE"
    exit 1
fi

echo "Successfully extracted LOGIN_URL: $LOGIN_URL" | tee -a "$LOG_FILE"

# Step 3: Perform the free login POST request
echo "Submitting free login credentials to Telekom portal..." | tee -a "$LOG_FILE"
LOGIN_REFERER="https://hotspot.t-mobile.net/wlan/rest/freeLogin"
POST_DATA="UserName=&Password=&FNAME=0&button=Login&OriginatingServer=http%3A%2F%2Fneverssl.com"

curl -m 15 -k -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
     -X POST \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -H "Referer: $LOGIN_REFERER" \
     -A "$USER_AGENT" \
     -d "$POST_DATA" \
     -o "$POST_RESPONSE_FILE" \
     "$LOGIN_URL"

# Step 4: Verify login via the logoffurl presence
LOGOFF_URL=$(cat "$POST_RESPONSE_FILE" | tr -d '\015' | sed -n 's/.*[Ll][Oo][Gg][Oo][Ff][Ff][Uu][Rr][Ll]>[[:space:]]*\([^<]*\)[[:space:]]*<\/[Ll][Oo][Gg][Oo][Ff][Ff][Uu][Rr][Ll]>.*/\1/p' | sed 's/&amp;/\&/g' | head -n 1)

if [ -n "$LOGOFF_URL" ]; then
    echo "SUCCESS: <logoffurl> detected ($LOGOFF_URL). Active session established!" | tee -a "$LOG_FILE"
else
    echo "WARNING: <logoffurl> not detected in POST response. Checking real internet status anyway..." | tee -a "$LOG_FILE"
fi

# CRITICAL MANDATORY VERIFICATION
echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
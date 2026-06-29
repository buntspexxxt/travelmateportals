#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching initial redirect URL..." | tee -a "$LOG_FILE"
# Using -v to capture output, extracting the location header
RESPONSE=$(curl -v -A "$USER_AGENT" -L "http://neverssl.com" 2>&1)
echo "Curl output captured." | tee -a "$LOG_FILE"

# Extract the URL from the response
EFFECTIVE_URL=$(echo "$RESPONSE" | grep -i "Location:" | tail -n 1 | sed -n 's/.*Location: //p' | tr -d '\\r')
echo "Extracted URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extract Query Parameters using sed
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*login.php?\(.*\)/\1/p')
echo "Query string: $QUERY_STRING" | tee -a "$LOG_FILE"

# Fetch the HTML form to get hidden fields
echo "Fetching portal page to extract hidden fields..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -v -A "$USER_AGENT" -b /tmp/c.txt -c /tmp/c.txt "$EFFECTIVE_URL")
echo "HTML retrieved." | tee -a "$LOG_FILE"

# Parse hidden fields
CHALLENGE=$(echo "$HTML_CONTENT" | grep -oP 'name="challenge" value="[^"]*"' | cut -d" -f4)
UAMIP=$(echo "$HTML_CONTENT" | grep -oP 'name="uamip" value="[^"]*"' | cut -d" -f4)
UAMPORT=$(echo "$HTML_CONTENT" | grep -oP 'name="uamport" value="[^"]*"' | cut -d" -f4)
NASID=$(echo "$HTML_CONTENT" | grep -oP 'name="nasid" value="[^"]*"' | cut -d" -f4)

# POST Data
POST_DATA="haveTerms=1&termsOK=on&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&nasid=$NASID&myLogin=agb&ll=de&custom=1&button=kostenlos+einloggen"

echo "Submitting login form..." | tee -a "$LOG_FILE"
LOGIN_RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/c.txt -c /tmp/c.txt -d "$POST_DATA" "https://www.hotsplots.de/auth/login.php")
echo "Login attempt complete." | tee -a "$LOG_FILE"

# Check connectivity
echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet connected." | tee -a "$LOG_FILE" && exit 0 || echo "Failure: Internet not reached." | tee -a "$LOG_FILE" && exit 1
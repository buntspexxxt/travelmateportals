#!/bin/bash

# SCRIPT_VERSION="1.1.0"

check_internet() {
    curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204" | grep -qE '204|200'
}

LOG_FILE=/tmp/portal_login.log
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a $LOG_FILE
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a $LOG_FILE
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching initial redirect to identify parameters..."
# Capture initial redirect to get parameters from the URL
REDIRECT_OUTPUT=$(curl -m 15 -v -A "$UA" http://detectportal.firefox.com/success.txt 2>&1)
LOCATION=$(echo "$REDIRECT_OUTPUT" | sed -n 's/.*Location: //p' | tr -d '\\r')

if [ -z "$LOCATION" ]; then
    echo "Error: Could not extract redirect URL."
    exit 1
fi

echo "Extracted Redirect URL: $LOCATION"

# Extract Query Parameters using POSIX sed
QUERY_STRING=$(echo "$LOCATION" | sed -n 's/.*\\?\\(.*\\)/\\1/p')

# The portal uses a session/resume API based on the JS logic
# Base URL is guest7.ic.peplink.com
API_BASE="https://guest7.ic.peplink.com/cp"

echo "Attempting to resume session via API..."
SESSION_RESPONSE=$(curl -m 15 -v -A "$UA" "$API_BASE/session/resume?$QUERY_STRING" -c /tmp/cookies.txt)
echo "API Response: $SESSION_RESPONSE"

# Proceed to login command as per JS logic
echo "Submitting login command..."
LOGIN_URL="$API_BASE/login?$QUERY_STRING&command=login&resume=true"
curl -m 15 -v -A "$UA" -b /tmp/cookies.txt "$LOGIN_URL"

# Final Connectivity Check
echo "Verifying connectivity..."
check_internet&& echo "Login Successful!" && exit 0 || exit 1

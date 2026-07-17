#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Prepare logging and cleanup
LOG_FILE="/tmp/portal_login.log"
touch "$LOG_FILE"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Starting Hotsplots login process" | tee -a "$LOG_FILE"

# Wait for network readiness
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

# Get initial redirect parameters
HTML_OUT=$(mktemp)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
echo "Fetching portal login page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "http://neverssl.com")

echo "Extracting form fields from HTML..."
HTML_CONTENT=$(cat "$HTML_OUT")
CHALLENGE=$(echo "$HTML_CONTENT" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML_CONTENT" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML_CONTENT" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
USERURL=$(echo "$HTML_CONTENT" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$HTML_CONTENT" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

if [ -z "$CHALLENGE" ]; then
    echo "Failed to extract portal parameters! Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting login form..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 \
    --data-urlencode "challenge=$CHALLENGE" \
    --data-urlencode "uamip=$UAMIP" \
    --data-urlencode "uamport=$UAMPORT" \
    --data-urlencode "userurl=$USERURL" \
    --data-urlencode "nasid=$NASID" \
    --data-urlencode "myLogin=agb" \
    --data-urlencode "ll=en" \
    --data-urlencode "custom=1" \
    "https://www.hotsplots.de/auth/login.php" 2>&1)

echo "HTTP Response captured: $RESPONSE" | tee -a "$LOG_FILE"

# Verification loop
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1
#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Standard Hotsplots Captive Portal Login Script
LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

echo "Starting Hotsplots login process..." | tee -a "$LOG_FILE"

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

echo "Fetching portal page to extract hidden parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" -w "%\{url_effective\}" -o "$HTML_OUT" -c "$COOKIE_FILE" -m 15 "http://neverssl.com")

if [ ! -s "$HTML_OUT" ]; then
    echo "Failed to retrieve portal page." | tee -a "$LOG_FILE"
    exit 1
fi

HTML=$(cat "$HTML_OUT")

echo "Parsing hidden form fields..." | tee -a "$LOG_FILE"
CHALLENGE=$(echo "$HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

if [ -z "$CHALLENGE" ]; then
    echo "Failed to extract challenge token. Is the portal already authenticated?" | tee -a "$LOG_FILE"
    exit 0
fi

echo "Found Challenge: $CHALLENGE. Submitting login request..." | tee -a "$LOG_FILE"

# Construct login URL based on common Hotsplots UAM structure
AUTH_URL="http://$UAMIP:$UAMPORT/auth/login.php"

RESPONSE_CODE=$(curl -k -v -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -m 15 \
    --data-urlencode "haveTerms=1" \
    --data-urlencode "termsOK=1" \
    --data-urlencode "challenge=$CHALLENGE" \
    --data-urlencode "uamip=$UAMIP" \
    --data-urlencode "uamport=$UAMPORT" \
    --data-urlencode "nasid=$NASID" \
    --data-urlencode "myLogin=agb" \
    --data-urlencode "button=kostenlos einloggen" \
    -w "%\{http_code\}" -o /dev/null "$AUTH_URL")

echo "HTTP Response Code: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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
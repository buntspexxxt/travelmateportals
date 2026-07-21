#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

echo "Starting Hotsplots login process for Stadtwerke_Neuss..." | tee -a "$LOG_FILE"

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

# Fetch the initial portal page
echo "Fetching captive portal page to extract parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -c "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "http://neverssl.com")

echo "Effective URL captured: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extract form data dynamically using sed
CHALLENGE=$(sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p' "$HTML_OUT")
UAMIP=$(sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p' "$HTML_OUT")
UAMPORT=$(sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p' "$HTML_OUT")
NASID=$(sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p' "$HTML_OUT")
USERURL=$(sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p' "$HTML_OUT")

if [ -z "$CHALLENGE" ]; then
    echo "ERROR: Could not extract dynamic challenge token." | tee -a "$LOG_FILE"
    exit 1
fi

# Submit form
echo "Submitting login form..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    --data-urlencode "haveTerms=1" \
    --data-urlencode "termsOK=on" \
    --data-urlencode "challenge=$CHALLENGE" \
    --data-urlencode "uamip=$UAMIP" \
    --data-urlencode "uamport=$UAMPORT" \
    --data-urlencode "userurl=$USERURL" \
    --data-urlencode "myLogin=agb" \
    --data-urlencode "ll=de" \
    --data-urlencode "nasid=$NASID" \
    --data-urlencode "custom=1" \
    --data-urlencode "button=kostenlos einloggen" \
    -w "%{http_code}" -o /dev/null -m 15 "https://www.hotsplots.de/auth/login.php")

echo "HTTP Response from login post: $RESPONSE_CODE" | tee -a "$LOG_FILE"

# Connectivity verification
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
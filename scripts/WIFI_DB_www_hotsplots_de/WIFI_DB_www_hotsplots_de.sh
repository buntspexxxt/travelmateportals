#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Starting portal login process..." | tee -a "$LOG_FILE"

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

HTML_OUT=$(mktemp)
trap 'rm -f "$HTML_OUT" "$COOKIE_FILE"' EXIT

echo "Fetching initial landing page to capture dynamic tokens..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -c "$COOKIE_FILE" -o "$HTML_OUT" -w "%\{url_effective\}" -m 15 "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Extracting hidden fields from HTML..." | tee -a "$LOG_FILE"
CHALLENGE=$(sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')
UAMIP=$(sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')
UAMPORT=$(sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')
NASID=$(sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')
USERURL=$(sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')

if [ -z "$CHALLENGE" ]; then
    echo "Error: Could not extract challenge token." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting login form..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST \
--data-urlencode "haveTerms=1" \
--data-urlencode "termsOK=on" \
--data-urlencode "challenge=$CHALLENGE" \
--data-urlencode "uamip=$UAMIP" \
--data-urlencode "uamport=$UAMPORT" \
--data-urlencode "userurl=$USERURL" \
--data-urlencode "myLogin=agb" \
--data-urlencode "nasid=$NASID" \
--data-urlencode "custom=1" \
-w "%\{http_code\}" -o /dev/null -m 15 "https://www.hotsplots.de/auth/login.php")

echo "Login submission HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

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
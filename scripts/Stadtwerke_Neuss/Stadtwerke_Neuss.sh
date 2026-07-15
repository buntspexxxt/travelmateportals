#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting login process" > "$LOG_FILE"

trap 'rm -f "$COOKIE_FILE" "$HTML_FILE"' EXIT
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)

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

echo "Fetching portal landing page..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_FILE" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" "http://neverssl.com" -m 15 | tr -d '\015')

if [ ! -s "$HTML_FILE" ]; then
    echo "Failed to download portal page" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracting hidden fields..."
HTML_CONTENT=$(cat "$HTML_FILE")
CHALLENGE=$(echo "$HTML_CONTENT" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML_CONTENT" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML_CONTENT" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$HTML_CONTENT" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')
USERURL=$(echo "$HTML_CONTENT" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p')

# Prepare POST data using encoded parameters
echo "Submitting login form..." | tee -a "$LOG_FILE"
POST_DATA="haveTerms=1&termsOK=on&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&nasid=$NASID&userurl=$USERURL&button=kostenlos+einloggen&myLogin=agb&ll=de&custom=1"

RESPONSE_CODE=$(curl -k -v -b "$COOKIE_FILE" -c "$COOKIE_FILE" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" -X POST "https://www.hotsplots.de/auth/login.php" -d "$POST_DATA" -w "%{http_code}" -o /dev/null -m 20 2>&1 | grep "HTTP/" | tail -n1)
echo "Login submission completed with status: $RESPONSE_CODE" | tee -a "$LOG_FILE"

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
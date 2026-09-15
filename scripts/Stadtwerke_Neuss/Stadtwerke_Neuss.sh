#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

echo "Starting Hotsplots login process for Stadtwerke_Neuss..." | tee -a "$LOG_FILE"

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

echo "Fetching initial captive portal page to extract tokens..." | tee -a "$LOG_FILE"
# Extract parameters directly from the URL
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -c "$COOKIE_FILE" -w "%\{url_effective\}" -o "$HTML_OUT" -m 15 "http://neverssl.com")

CHALLENGE=$(echo "$EFFECTIVE_URL" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
UAMIP=$(echo "$EFFECTIVE_URL" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$EFFECTIVE_URL" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
NASID=$(echo "$EFFECTIVE_URL" | sed -n 's/.*nasid=\([^&]*\).*/\1/p')
USERURL=$(echo "$EFFECTIVE_URL" | sed -n 's/.*userurl=\([^&]*\).*/\1/p')

if [ -z "$CHALLENGE" ]; then
    echo "ERROR: Could not extract dynamic challenge token from URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting form with AGB acceptance..." | tee -a "$LOG_FILE"
# The portal requires haveTerms=1 and termsOK=1 as hidden fields
RESPONSE_CODE=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    --data-urlencode "haveTerms=1" \
    --data-urlencode "termsOK=1" \
    --data-urlencode "challenge=$CHALLENGE" \
    --data-urlencode "uamip=$UAMIP" \
    --data-urlencode "uamport=$UAMPORT" \
    --data-urlencode "userurl=$USERURL" \
    --data-urlencode "myLogin=agb" \
    --data-urlencode "ll=de" \
    --data-urlencode "nasid=$NASID" \
    --data-urlencode "custom=1" \
    --data-urlencode "button=kostenlos einloggen" \
    -w "%\{http_code\}" -o /dev/null -m 15 "https://www.hotsplots.de/auth/login.php")

echo "HTTP Response from login post: $RESPONSE_CODE" | tee -a "$LOG_FILE"

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
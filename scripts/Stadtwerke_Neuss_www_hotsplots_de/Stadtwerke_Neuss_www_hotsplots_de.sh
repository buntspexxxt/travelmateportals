#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "${COOKIE_FILE}" "${HTML_FILE}"' EXIT
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
    i=$(($i + 1))
done

echo "Fetching landing page..." | tee -a "$LOG_FILE"
curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -m 15 -o "$HTML_FILE" "http://neverssl.com" >/dev/null 2>&1

HTML=$(cat "$HTML_FILE")
CHALLENGE=$(echo "$HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
USERURL=$(echo "$HTML" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

echo "Submitting form to Hotsplots..." | tee -a "$LOG_FILE"
REDIRECT_HTML=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 \
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
    "https://www.hotsplots.de/auth/login.php")

echo "Extracting CoovaChilli redirect URL from response..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(echo "$REDIRECT_HTML" | sed -n 's/.*url=\([^"]*\)".*/\1/p' | tr -d '\015')

if [ -n "$REDIRECT_URL" ]; then
    echo "Following CoovaChilli redirect: $REDIRECT_URL" | tee -a "$LOG_FILE"
    curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -m 15 "$REDIRECT_URL" >/dev/null 2>&1
else
    echo "No direct redirect found. Proceeding to connectivity check." | tee -a "$LOG_FILE"
fi

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$(($i + 1))
done
echo "ERROR: Connection not established." | tee -a "$LOG_FILE"
exit 1
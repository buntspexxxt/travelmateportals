#!/bin/sh
# SCRIPT_VERSION="1.0.0"
trap 'rm -f "${COOKIE_FILE}" "${HTML_FILE}"' EXIT
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
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
    i=$(($i + 1))
done

echo "Fetching portal page..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -m 15 -L -o "$HTML_FILE" "http://neverssl.com"

HTML=$(cat "$HTML_FILE")
CHALLENGE=$(echo "$HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
USERURL=$(echo "$HTML" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

echo "Submitting acceptance form..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 \
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
    "https://www.hotsplots.de/auth/login.php"

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
    i=$(($i + 1))
done
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1
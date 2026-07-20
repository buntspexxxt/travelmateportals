#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for IP, Gateway, and DNS..." >> "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" >> "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$(($i + 1))
done

echo "Fetching initial portal page..." >> "$LOG_FILE"
curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -m 15 -L -o "$HTML_FILE" "http://neverssl.com"

get_input_value() {
    sed -n "s/.*name="$1" value="\([^"]*\)".*/\1/p" "$HTML_FILE" | head -n 1 | tr -d '\015'
}

CHALLENGE=$(get_input_value "challenge")
UAMIP=$(get_input_value "uamip")
UAMPORT=$(get_input_value "uamport")
USERURL=$(get_input_value "userurl")
MYLOGIN=$(get_input_value "myLogin")
LL=$(get_input_value "ll")
NASID=$(get_input_value "nasid")
CUSTOM=$(get_input_value "custom")

if [ -z "$CHALLENGE" ]; then
    echo "Failed to extract portal parameters. Exiting." >> "$LOG_FILE"
    exit 1
fi

echo "Submitting terms acceptance via POST..." >> "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 -L \
    --data-urlencode "haveTerms=1" \
    --data-urlencode "termsOK=on" \
    --data-urlencode "challenge=$CHALLENGE" \
    --data-urlencode "uamip=$UAMIP" \
    --data-urlencode "uamport=$UAMPORT" \
    --data-urlencode "userurl=$USERURL" \
    --data-urlencode "myLogin=${MYLOGIN:-agb}" \
    --data-urlencode "ll=${LL:-de}" \
    --data-urlencode "nasid=$NASID" \
    --data-urlencode "custom=${CUSTOM:-1}" \
    --data-urlencode "button=kostenlos einloggen" \
    "https://www.hotsplots.de/auth/login.php")

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." >> "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" >> "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." >> "$LOG_FILE"
    sleep 4
    i=$(($i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." >> "$LOG_FILE"
exit 1
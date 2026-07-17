#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

decode_html_entities() {
    local val="$1"
    echo "$val" | sed 's/&quot;/"/g; s/&amp;/\&/g; s/&#x27;/\'/g; s/&#39;/\'/g; s/&lt;/</g; s/&gt;/>/g; s/&#x3D;/=/g; s/&#61;/=/g;'
}

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -m 15 -L -o "$HTML_FILE" "http://neverssl.com"
HTML=$(cat "$HTML_FILE")

get_input_value() {
    local name="$1"
    echo "$HTML" | sed -n "s/.*name="$name"[^>]*value="\([^"]*\)".*/\1/p; s/.*value="\([^"]*\)"[^>]*name="$name".*/\1/p" | head -n 1
}

CHALLENGE=$(get_input_value "challenge")
UAMIP=$(get_input_value "uamip")
UAMPORT=$(get_input_value "uamport")
USERURL=$(get_input_value "userurl")
MYLOGIN=$(get_input_value "myLogin")
LL=$(get_input_value "ll")
NASID=$(get_input_value "nasid")
CUSTOM=$(get_input_value "custom")

POST_URL="https://www.hotsplots.de/auth/login.php"
echo "Submitting acceptance..." | tee -a "$LOG_FILE"

curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 -L \
    --data-urlencode "haveTerms=1" \
    --data-urlencode "termsOK=on" \
    --data-urlencode "challenge=$CHALLENGE" \
    --data-urlencode "uamip=$UAMIP" \
    --data-urlencode "uamport=$UAMPORT" \
    --data-urlencode "userurl=$USERURL" \
    --data-urlencode "myLogin=$MYLOGIN" \
    --data-urlencode "ll=$LL" \
    --data-urlencode "nasid=$NASID" \
    --data-urlencode "custom=$CUSTOM" \
    --data-urlencode "button=kostenlos einloggen" \
    "$POST_URL" | tee -a "$LOG_FILE"

echo "Verifying connectivity..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Connected!" | tee -a "$LOG_FILE"
        exit 0
    fi
    sleep 4
    i=$((i + 1))
done
exit 1
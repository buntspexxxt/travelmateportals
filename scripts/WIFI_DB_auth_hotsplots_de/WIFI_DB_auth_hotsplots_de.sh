#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_log.txt"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_FILE"' EXIT

echo "Starting Hotsplots/WIFI@DB login process..." | tee -a "$LOG_FILE"

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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" -w "%\{url_effective\}" -m 15 "http://neverssl.com" | tr -d '\015')

HTML_CONTENT=$(cat "$HTML_FILE")
CHALLENGE=$(echo "$HTML_CONTENT" | sed -n 's/.*id="login_status_form_challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML_CONTENT" | sed -n 's/.*id="login_status_form_uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML_CONTENT" | sed -n 's/.*id="login_status_form_uamport" value="\([^"]*\)".*/\1/p')
TOKEN=$(echo "$HTML_CONTENT" | sed -n 's/.*id="login_status_form__token" value="\([^"]*\)".*/\1/p')

if [ -n "$CHALLENGE" ]; then
    echo "Submitting login form..." | tee -a "$LOG_FILE"
    curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 \
        --data-urlencode "login_status_form[button]=Jetzt kostenlos surfen" \
        --data-urlencode "login_status_form[challenge]=$CHALLENGE" \
        --data-urlencode "login_status_form[uamip]=$UAMIP" \
        --data-urlencode "login_status_form[uamport]=$UAMPORT" \
        --data-urlencode "login_status_form[_token]=$TOKEN" \
        -o "$HTML_FILE" "$EFFECTIVE_URL"
else
    echo "No challenge found, checking if already authorized..." | tee -a "$LOG_FILE"
fi

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Waiting for internet..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done
echo "ERROR: Portal request completed but no Internet connectivity established." | tee -a "$LOG_FILE"
exit 1
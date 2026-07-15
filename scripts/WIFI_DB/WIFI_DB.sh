#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_log.txt"
touch "$LOG_FILE"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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
HTML_OUT=$(mktemp)
curl -k -L -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -o "$HTML_OUT" -w "%{url_effective}" "http://neverssl.com" > "$LOG_FILE" 2>&1
LANDING_URL=$(cat "$LOG_FILE" | grep -o 'https://[^ ]*')
echo "Effective URL: $LANDING_URL" | tee -a "$LOG_FILE"

HTML=$(cat "$HTML_OUT")
CHALLENGE=$(echo "$HTML" | sed -n 's/.*name="login_status_form\[challenge\]" value="\([^"]*\)".*/\1/p')
TOKEN=$(echo "$HTML" | sed -n 's/.*name="login_status_form\[_token\]" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML" | sed -n 's/.*name="login_status_form\[uamip\]" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML" | sed -n 's/.*name="login_status_form\[uamport\]" value="\([^"]*\)".*/\1/p')

echo "Extracted Challenge: $CHALLENGE" | tee -a "$LOG_FILE"
echo "Extracted Token: $TOKEN" | tee -a "$LOG_FILE"

if [ -z "$TOKEN" ]; then
    echo "Failed to extract token. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting login form..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
--data-urlencode "login_status_form[button]=Jetzt kostenlos surfen" \
--data-urlencode "login_status_form[challenge]=$CHALLENGE" \
--data-urlencode "login_status_form[uamip]=$UAMIP" \
--data-urlencode "login_status_form[uamport]=$UAMPORT" \
--data-urlencode "login_status_form[_token]=$TOKEN" \
"$LANDING_URL" 2>&1)

echo "Response received." | tee -a "$LOG_FILE"

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
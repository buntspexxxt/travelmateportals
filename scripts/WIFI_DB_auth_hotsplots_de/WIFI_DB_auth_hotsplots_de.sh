#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_log.txt"
echo "Starting Hotsplots login process..." | tee -a "$LOG_FILE"

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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching portal page..." | tee -a "$LOG_FILE"
# Get initial redirect to extract parameters
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" -w "%{url_effective}" -m 15 "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Parse hidden form fields for the login submission
HTML_CONTENT=$(cat "$HTML_FILE")
CHALLENGE=$(echo "$HTML_CONTENT" | sed -n 's/.*id="login_status_form_challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML_CONTENT" | sed -n 's/.*id="login_status_form_uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML_CONTENT" | sed -n 's/.*id="login_status_form_uamport" value="\([^"]*\)".*/\1/p')
TOKEN=$(echo "$HTML_CONTENT" | sed -n 's/.*id="login_status_form__token" value="\([^"]*\)".*/\1/p')

if [ -z "$CHALLENGE" ]; then
    echo "Error: Could not extract form parameters. Portal might be already authenticated." | tee -a "$LOG_FILE"
else
    echo "Submitting acceptance form..." | tee -a "$LOG_FILE"
    RESPONSE_CODE=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 \
        --data-urlencode "login_status_form[button]=Jetzt kostenlos surfen" \
        --data-urlencode "login_status_form[challenge]=$CHALLENGE" \
        --data-urlencode "login_status_form[uamip]=$UAMIP" \
        --data-urlencode "login_status_form[uamport]=$UAMPORT" \
        --data-urlencode "login_status_form[_token]=$TOKEN" \
        -w "%{http_code}" -o /dev/null "$EFFECTIVE_URL")
    echo "HTTP Response from login: $RESPONSE_CODE" | tee -a "$LOG_FILE"
fi

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
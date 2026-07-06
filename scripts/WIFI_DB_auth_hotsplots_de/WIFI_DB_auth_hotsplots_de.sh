#!/bin/sh
# SCRIPT_VERSION="1.1.0"

LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/hotsplots_cookies.txt"
LANDING_HTML="/tmp/hotsplots_landing.html"
rm -f "$COOKIE_FILE" "$LANDING_HTML"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in $(seq 1 20); do
    if ip route | grep -q default; then
        echo "Network interface ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Step 1: Fetching initial portal redirect from neverssl.com..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -w "%{url_effective}" -o "$LANDING_HTML" "http://neverssl.com")
echo "Captured Landing URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

if [ ! -f "$LANDING_HTML" ] || [ -z "$EFFECTIVE_URL" ]; then
    echo "ERROR: Failed to retrieve portal landing page." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Step 2: Extracting hidden form parameters and CSRF token..." | tee -a "$LOG_FILE"
CHALLENGE=$(grep -i 'login_status_form\[challenge\]' "$LANDING_HTML" | sed -n 's/.*value="\([^"]*\)".*/\1/p')
UAMIP=$(grep -i 'login_status_form\[uamip\]' "$LANDING_HTML" | sed -n 's/.*value="\([^"]*\)".*/\1/p')
UAMPORT=$(grep -i 'login_status_form\[uamport\]' "$LANDING_HTML" | sed -n 's/.*value="\([^"]*\)".*/\1/p')
TOKEN=$(grep -i 'login_status_form\[_token\]' "$LANDING_HTML" | sed -n 's/.*value="\([^"]*\)".*/\1/p')

echo "Extracted Tokens -> Challenge: $CHALLENGE | UamIP: $UAMIP | Token: ${TOKEN:0:15}..." | tee -a "$LOG_FILE"

echo "Step 3: Submitting login form ('Jetzt kostenlos surfen')..." | tee -a "$LOG_FILE"
POST_RES=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -X POST \
  --data-urlencode "login_status_form[button]=" \
  --data-urlencode "login_status_form[challenge]=$CHALLENGE" \
  --data-urlencode "login_status_form[uamip]=$UAMIP" \
  --data-urlencode "login_status_form[uamport]=$UAMPORT" \
  --data-urlencode "login_status_form[ll]=" \
  --data-urlencode "login_status_form[myLogin]=" \
  --data-urlencode "login_status_form[_token]=$TOKEN" \
  "$EFFECTIVE_URL" 2>&1)

echo "Response summary: $(echo "$POST_RES" | grep -i 'HTTP/' | tail -n 2)" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    rm -f "$COOKIE_FILE" "$LANDING_HTML"
    exit 0
else
    echo "ERROR: Internet connectivity check failed (HTTP Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    rm -f "$COOKIE_FILE" "$LANDING_HTML"
    exit 1
fi
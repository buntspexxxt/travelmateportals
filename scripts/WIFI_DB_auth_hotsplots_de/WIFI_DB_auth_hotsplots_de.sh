#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/hotsplots_cookies.txt"
HTML_OUT="/tmp/portal_page.html"

echo "Starting Hotsplots authentication process..." | tee -a "$LOG_FILE"

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

echo "Fetching initial redirect URL..." | tee -a "$LOG_FILE"
# Use curl to get the initial redirect page where the parameters are located
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_OUT" -A "$USER_AGENT" -c "$COOKIE_FILE" "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Extracting dynamic form fields from HTML..." | tee -a "$LOG_FILE"
CHALLENGE=$(sed -n 's/.*id="login_status_form_challenge" name="login_status_form\\[challenge\\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')
UAMIP=$(sed -n 's/.*id="login_status_form_uamip" name="login_status_form\\[uamip\\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')
UAMPORT=$(sed -n 's/.*id="login_status_form_uamport" name="login_status_form\\[uamport\\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')
TOKEN=$(sed -n 's/.*id="login_status_form__token" name="login_status_form\\[_token\\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')

if [ -z "$CHALLENGE" ]; then
    echo "ERROR: Could not extract form tokens." | tee -a "$LOG_FILE"
    exit 1
fi

# Construct the submit URL from the base of the redirect URL
BASE_URL=$(echo "$EFFECTIVE_URL" | cut -d'?' -f1)
echo "Submitting form to $BASE_URL..." | tee -a "$LOG_FILE"

RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -o "$HTML_OUT" \
  --data-urlencode "login_status_form[button]=Jetzt kostenlos surfen" \
  --data-urlencode "login_status_form[challenge]=$CHALLENGE" \
  --data-urlencode "login_status_form[uamip]=$UAMIP" \
  --data-urlencode "login_status_form[uamport]=$UAMPORT" \
  --data-urlencode "login_status_form[ll]=" \
  --data-urlencode "login_status_form[myLogin]=" \
  --data-urlencode "login_status_form[_token]=$TOKEN" \
  "$BASE_URL" 2>&1)

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
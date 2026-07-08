#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/hotsplots_cookies.txt"
HTML_OUT="/tmp/portal_page.html"

echo "Starting Hotsplots authentication process..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 2
done

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
# Extracting the target URL from a reliable redirect
EFFECTIVE_URL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o "$HTML_OUT" "http://neverssl.com" 2>&1 | grep "Location:" | sed 's/Location: //g' | sed 's/\r//g' | tail -n1)

# Fallback if redirect header capture fails
[ -z "$EFFECTIVE_URL" ] && EFFECTIVE_URL="https://auth.hotsplots.de/login"

echo "Parsing hidden fields from HTML..." | tee -a "$LOG_FILE"
CHALLENGE=$(sed -n 's/.*id="login_status_form_challenge" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | sed 's/\r//g')
UAMIP=$(sed -n 's/.*id="login_status_form_uamip" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | sed 's/\r//g')
UAMPORT=$(sed -n 's/.*id="login_status_form_uamport" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | sed 's/\r//g')
TOKEN=$(sed -n 's/.*id="login_status_form__token" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | sed 's/\r//g')

echo "Submitting form with extracted parameters..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -o "$HTML_OUT" \
  --data-urlencode "login_status_form[button]=Jetzt kostenlos surfen" \
  --data-urlencode "login_status_form[challenge]=$CHALLENGE" \
  --data-urlencode "login_status_form[uamip]=$UAMIP" \
  --data-urlencode "login_status_form[uamport]=$UAMPORT" \
  --data-urlencode "login_status_form[ll]=" \
  --data-urlencode "login_status_form[myLogin]=" \
  --data-urlencode "login_status_form[_token]=$TOKEN" \
  "$EFFECTIVE_URL" 2>&1)

echo "HTTP Request Result: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: No Internet connectivity (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
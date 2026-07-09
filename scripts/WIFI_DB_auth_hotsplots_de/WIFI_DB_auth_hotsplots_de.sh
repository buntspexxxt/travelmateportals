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
curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o "$HTML_OUT" "http://neverssl.com" > /tmp/curl_debug.txt 2>&1

echo "Parsing hidden form fields..." | tee -a "$LOG_FILE"
CHALLENGE=$(sed -n 's/.*name="login_status_form\[challenge\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')
UAMIP=$(sed -n 's/.*name="login_status_form\[uamip\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')
UAMPORT=$(sed -n 's/.*name="login_status_form\[uamport\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')
TOKEN=$(sed -n 's/.*name="login_status_form\[_token\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')

echo "Submitting acceptance form to Hotsplots..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o "$HTML_OUT" \
  --data-urlencode "login_status_form[button]=Jetzt kostenlos surfen" \
  --data-urlencode "login_status_form[challenge]=$CHALLENGE" \
  --data-urlencode "login_status_form[uamip]=$UAMIP" \
  --data-urlencode "login_status_form[uamport]=$UAMPORT" \
  --data-urlencode "login_status_form[ll]=" \
  --data-urlencode "login_status_form[myLogin]=" \
  --data-urlencode "login_status_form[_token]=$TOKEN" \
  "https://auth.hotsplots.de/login" -w "%{http_code}")

echo "HTTP Response Code: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/hotsplots_cookies.txt"
HTML_OUT="/tmp/portal_page.html"

echo "Waiting for network..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
done

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
# Fetching the page to initialize session and extract dynamic form tokens
curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o "$HTML_OUT" "http://neverssl.com" 2>&1 | tee -a "$LOG_FILE"

CHALLENGE=$(sed -n 's/.*name="login_status_form\[challenge\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT")
UAMIP=$(sed -n 's/.*name="login_status_form\[uamip\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT")
UAMPORT=$(sed -n 's/.*name="login_status_form\[uamport\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT")
TOKEN=$(sed -n 's/.*name="login_status_form\[_token\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT")

echo "Found Challenge: $CHALLENGE" | tee -a "$LOG_FILE"

# The form POSTs to the same URI. We extract the action URL if possible, or default to the base domain auth path.
AUTH_URL="https://auth.hotsplots.de/login"

echo "Submitting authentication..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L \
  --data-urlencode "login_status_form[button]=Jetzt kostenlos surfen" \
  --data-urlencode "login_status_form[challenge]=$CHALLENGE" \
  --data-urlencode "login_status_form[uamip]=$UAMIP" \
  --data-urlencode "login_status_form[uamport]=$UAMPORT" \
  --data-urlencode "login_status_form[ll]=" \
  --data-urlencode "login_status_form[myLogin]=" \
  --data-urlencode "login_status_form[_token]=$TOKEN" \
  "$AUTH_URL" 2>&1)

echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
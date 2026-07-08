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

echo "Fetching initial portal page and detecting redirect..." | tee -a "$LOG_FILE"
# Fetch neverssl.com, follow redirects, save the final landing URL in FINAL_URL.
# Stderr (verbose log and progress) is saved to the log file.
FINAL_URL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o "$HTML_OUT" -w "%{url_effective}" "http://neverssl.com" 2>>"$LOG_FILE")

echo "Effective Landing URL: $FINAL_URL" | tee -a "$LOG_FILE"

if [ -z "$FINAL_URL" ] || [ "$FINAL_URL" = "http://neverssl.com" ] || [ "$FINAL_URL" = "http://neverssl.com/" ]; then
    echo "ERROR: Failed to capture the redirect URL. We might already be logged in, or there is no captive portal redirect." | tee -a "$LOG_FILE"
fi

echo "Parsing hidden fields from HTML..." | tee -a "$LOG_FILE"
CHALLENGE=$(sed -n 's/.*name="login_status_form\[challenge\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | sed 's/\r//g')
UAMIP=$(sed -n 's/.*name="login_status_form\[uamip\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | sed 's/\r//g')
UAMPORT=$(sed -n 's/.*name="login_status_form\[uamport\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | sed 's/\r//g')
TOKEN=$(sed -n 's/.*name="login_status_form\[_token\]" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | sed 's/\r//g')

echo "Parsed parameters:" | tee -a "$LOG_FILE"
echo "  CHALLENGE: $CHALLENGE" | tee -a "$LOG_FILE"
echo "  UAMIP: $UAMIP" | tee -a "$LOG_FILE"
echo "  UAMPORT: $UAMPORT" | tee -a "$LOG_FILE"
echo "  TOKEN: $TOKEN" | tee -a "$LOG_FILE"

if [ -z "$TOKEN" ]; then
    echo "ERROR: Could not parse token from HTML! Portal structure might have changed." | tee -a "$LOG_FILE"
fi

echo "Submitting login POST request..." | tee -a "$LOG_FILE"
# Post the login form to the dynamic FINAL_URL which has all session query parameters
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L \
  --data-urlencode "login_status_form[button]=Jetzt kostenlos surfen" \
  --data-urlencode "login_status_form[challenge]=$CHALLENGE" \
  --data-urlencode "login_status_form[uamip]=$UAMIP" \
  --data-urlencode "login_status_form[uamport]=$UAMPORT" \
  --data-urlencode "login_status_form[ll]=" \
  --data-urlencode "login_status_form[myLogin]=" \
  --data-urlencode "login_status_form[_token]=$TOKEN" \
  "$FINAL_URL" 2>>"$LOG_FILE")

echo "POST completed. Logged response output (first 200 chars):" | tee -a "$LOG_FILE"
echo "$RESPONSE" | head -c 200 >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
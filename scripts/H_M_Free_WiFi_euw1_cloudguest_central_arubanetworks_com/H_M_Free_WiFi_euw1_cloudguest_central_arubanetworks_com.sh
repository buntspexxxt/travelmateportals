#!/bin/sh
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting H&M Free WiFi authentication process" | tee -a "$LOG_FILE"

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

echo "Fetching initial portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -w "%{url_effective}" -A "$USER_AGENT" -o /dev/null -m 15 "http://neverssl.com" | tr -d '\015')
echo "Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Capturing the JavaScript redirect location..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -k -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -m 15 "$REDIRECT_URL")
# Extracting the URL from window.top.location.href or META refresh using sed
LOGIN_URL=$(echo "$HTML_CONTENT" | sed -n 's/.*window.top.location.href = "\([^"]*\)".*/\1/p' | head -n 1)
[ -z "$LOGIN_URL" ] && LOGIN_URL=$(echo "$HTML_CONTENT" | sed -n 's/.*URL=\([^ "]*\).*/\1/p' | head -n 1)
echo "Extracted Login URL: $LOGIN_URL" | tee -a "$LOG_FILE"

echo "Navigating to login page to trigger session..." | tee -a "$LOG_FILE"
curl -k -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -o /dev/null -m 15 "$LOGIN_URL"

echo "Submitting authentication..." | tee -a "$LOG_FILE"
# The portal typically uses the capture token as part of the session state. We perform a GET to finalize.
FINAL_CHECK=$(curl -k -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -w "%{http_code}" -o /dev/null -m 15 "$LOGIN_URL")
echo "Login submission response code: $FINAL_CHECK" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: No internet (Code: $CHECK_CODE)"
    exit 1
fi
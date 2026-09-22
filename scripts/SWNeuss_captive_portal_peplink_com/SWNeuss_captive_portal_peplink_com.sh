#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/120.0.0.0"

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
    i=$((i + 1))
done

echo "Fetching initial splash page..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_OUT" -A "$USER_AGENT" "http://neverssl.com")
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*\?\(.*\)/\1/p')

echo "Extracting Grant URL and performing login..." | tee -a "$LOG_FILE"
# The portal provides a link with class 'button' that contains the grant path
GRANT_URL=$(grep -oE 'https://eu.network-auth.com/splash/[^/]+/grant\?continue_url=[^"]+' "$HTML_OUT" | head -n 1 | sed 's/&amp;/\&/g')

if [ -z "$GRANT_URL" ]; then
    echo "Could not find grant URL. Analyzing page..." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting grant request to: $GRANT_URL" | tee -a "$LOG_FILE"
# Perform the grant request using HEAD as implied by the page JS
RESPONSE_CODE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 -o /dev/null -w "%{http_code}" "$GRANT_URL")
echo "HTTP Response Code: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        rm -f "$HTML_OUT"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done
rm -f "$HTML_OUT"
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1
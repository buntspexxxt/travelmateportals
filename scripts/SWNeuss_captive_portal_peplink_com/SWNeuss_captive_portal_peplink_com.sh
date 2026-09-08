#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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

echo "Fetching initial portal page to get session cookies..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o "$HTML_OUT" "http://neverssl.com"

echo "Extracting grant URL from HTML..." | tee -a "$LOG_FILE"
# The portal requires hitting the /grant endpoint. We extract the URL from the button href attribute.
GRANT_URL=$(sed -n 's/.*<a class="button" href="\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | sed 's/&amp;/\&/g')

if [ -z "$GRANT_URL" ]; then
    echo "ERROR: Could not extract GRANT_URL" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Executing grant request to authorize..." | tee -a "$LOG_FILE"
# Based on the JS, the portal performs a HEAD request to the current location to get a header, then navigates.
# We follow the redirect to the final auth state.
RESPONSE_CODE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -w "% {http_code}" -o /dev/null "$GRANT_URL")
echo "Grant response code: $RESPONSE_CODE" | tee -a "$LOG_FILE"

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
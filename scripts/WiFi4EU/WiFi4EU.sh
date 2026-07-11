#!/bin/bash
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for network connectivity..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Fetching landing page to extract session and path..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -m 15 -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" -w "%{url_effective}" "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# The portal provides a 'Get Online' link with a specific ID, which acts as the 'Accept' button.
echo "Extracting 'Get Online' link from HTML..."
GET_ONLINE_URL=$(sed -n 's/.*<a class="actionable" href="\([^"]*\)">.*Get Online.*/\1/p' "$HTML_FILE" | tr -d '\015')

if [ -z "$GET_ONLINE_URL" ]; then
    echo "ERROR: Could not find 'Get Online' link in portal page." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Clicking 'Get Online' action at: $GET_ONLINE_URL" | tee -a "$LOG_FILE"
# The portal often uses a sequence of redirects to validate the session. We must follow them.
curl -m 15 -k -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$GET_ONLINE_URL" -o /dev/null

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
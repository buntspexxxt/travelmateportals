#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

echo "Starting IKEA WiFi login process..." | tee -a "$LOG_FILE"

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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching captive portal redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_OUT" -A "$USER_AGENT" -m 15 "http://neverssl.com")
REDIRECT_URL=$(echo "$REDIRECT_URL" | tr -d '\015')
echo "Effective URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Submitting acceptance POST request..." | tee -a "$LOG_FILE"
# The Aruba Cloud Guest portal logic involves a redirect to a login page containing a capture token.
# We follow the flow by submitting the form associated with the login page.
# IKEA portals typically require accepting terms via a POST to the same endpoint or a /submit endpoint.
# Extracting the 'capture' param which acts as the session token.
CAPTURE_TOKEN=$(echo "$REDIRECT_URL" | sed -n 's/.*capture=\([^&]*\).*/\1/p')
BASE_URL=$(echo "$REDIRECT_URL" | sed 's/\/login.*/\/submit/')

RESPONSE_CODE=$(curl -k -s -o "$HTML_OUT" -w "%{http_code}" -A "$USER_AGENT" -m 15 \
    -d "capture=$CAPTURE_TOKEN" \
    -d "accept=true" \
    "$BASE_URL")

echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

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
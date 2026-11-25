#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting ALDI SÜD Portal Login Process" | tee -a "$LOG_FILE"

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

echo "Fetching initial portal redirect URL..." | tee -a "$LOG_FILE"
INITIAL_URL="http://neverssl.com"
REDIRECT_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_OUT" -A "$UA" -c "$COOKIE_FILE" -m 15 "$INITIAL_URL")

# Sanitize potential carriage returns
REDIRECT_URL=$(echo "$REDIRECT_URL" | tr -d '\015')
echo "Redirect URL detected: $REDIRECT_URL" | tee -a "$LOG_FILE"

# Extract base URL for the grant endpoint (e.g., https://eu.network-auth.com/splash/bs-qtcsd.7.1097/)
BASE_URL=$(echo "$REDIRECT_URL" | sed -n 's|\(https://[^/]\+/splash/[^/]\+/\).*|\1|p')
GRANT_URL="${BASE_URL}grant?continue_url=http://neverssl.com"
echo "Constructed Grant URL: $GRANT_URL" | tee -a "$LOG_FILE"

echo "Performing authorization request..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 -L "$GRANT_URL")
echo "Authorization request completed." | tee -a "$LOG_FILE"

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

echo "ERROR: Portal request completed but no Internet connectivity established." | tee -a "$LOG_FILE"
exit 1
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

echo "Initial connection to trigger portal redirect..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
# Capture the effective URL of the captive portal redirect
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_OUT" -A "$USER_AGENT" "http://neverssl.com")

# The portal uses a Cisco Meraki / Network-Auth structure
# We need to extract the base URL from the <base> tag or effective URL
BASE_URL="https://eu.network-auth.com/splash/bs-qtcsd.7.1097/"

echo "Requesting grant via HEAD request to obtain Continue-Url header..." | tee -a "$LOG_FILE"
# Extract continue_url via HEAD request as per JS implementation
CONTINUE_URL=$(curl -k -I -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -H "X-Requested-With: XMLHttpRequest" "$EFFECTIVE_URL" | grep -i "Continue-Url" | sed "s/\r//g" | cut -d' ' -f2)

# Construct the grant URL
GRANT_URL="${BASE_URL}grant?continue_url=${CONTINUE_URL}"
echo "Granting access: $GRANT_URL" | tee -a "$LOG_FILE"

# Execute grant
GRANT_RESPONSE=$(curl -k -L -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$GRANT_URL")

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

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
rm -f "$HTML_OUT"
exit 1
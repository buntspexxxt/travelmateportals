#!/bin/bash
# SCRIPT_VERSION="1.1.1"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}" "${HTML_FILE2:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
HTML_FILE2=$(mktemp)

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 2
done

echo "Fetching initial splash page..." | tee -a "$LOG_FILE"
# The portal requires a cookie-enabled session. Using curl to visit the landing page to get the session cookie.
curl -m 15 -k -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o "$HTML_FILE" "http://neverssl.com"

echo "Submitting registration form (The Cloud 'Continue' button)..." | tee -a "$LOG_FILE"
# The form at https://service.thecloud.eu/service-platform/macauthlogin/v5/registration requires a POST request.
# Based on the HTML, there are no hidden input fields needed besides standard session cookies.
# We post an empty body to simulate clicking 'Continue' (or a simple form submission) as observed in 'The Cloud' portals.
RESPONSE_CODE=$(curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -w "%{http_code}" -o "$HTML_FILE2" -d "" "https://service.thecloud.eu/service-platform/macauthlogin/v5/registration")

echo "HTTP Response Code from registration: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
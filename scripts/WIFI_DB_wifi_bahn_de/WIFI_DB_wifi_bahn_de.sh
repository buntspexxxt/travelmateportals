#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_JAR="/tmp/db_cookies.txt"
HTML_PAGE="/tmp/db_landing.html"

echo "Starting login process for WIFI_DB_wifi_bahn_de" | tee -a "$LOG_FILE"

# 1. Wait for DHCP
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# Check if already online
CHECK_CODE=$(curl -k -o /dev/null -w "%{http_code}" -m 5 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "Already online." | tee -a "$LOG_FILE"
    exit 0
fi

# 2. Fetch the registration page to get cookies and form state
echo "Fetching registration page..." | tee -a "$LOG_FILE"
curl -k -L -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "https://service.thecloud.eu/service-platform/macauthlogin/v5" > "$HTML_PAGE"

# 3. Extract form action (The Cloud uses dynamic paths)
FORM_ACTION=$(sed -n 's/.*id="registration" method="POST" action="\([^"]*\)".*/\1/p' "$HTML_PAGE")
echo "Form action: $FORM_ACTION" | tee -a "$LOG_FILE"

# 4. Submit form (The Cloud 'One-Click' portal requires empty POST)
echo "Submitting registration form..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X POST "$FORM_ACTION" -d "" 2>&1 | tee -a "$LOG_FILE"

# 5. Verify connectivity
echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    rm -f "$COOKIE_JAR" "$HTML_PAGE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
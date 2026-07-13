#!/bin/sh

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"

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

echo "Fetching initial captive portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -w "%{url_effective}" -A "$USER_AGENT" -o /dev/null -s -m 15 "http://neverssl.com" | tr -d '\015')
echo "Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Downloading portal landing page to find form tokens..." | tee -a "$LOG_FILE"
PORTAL_HTML=$(curl -k -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -m 15 "$REDIRECT_URL")

echo "Extracting form action and hidden fields..."
ACTION_URL=$(echo "$PORTAL_HTML" | sed -n 's/.*action="\([^"]*\)".*/\1/p' | head -n 1)
# If action is relative, prepend base domain
if [ "${ACTION_URL#/}" != "$ACTION_URL" ]; then
    BASE_URL=$(echo "$REDIRECT_URL" | cut -d/ -f1-3)
    ACTION_URL="${BASE_URL}${ACTION_URL}"
fi

# Extracting typical Aruba CloudGuest hidden fields (e.g., cmd, mac, etc)
# Aruba portals usually require POSTing the parameters back
QUERY_PARAMS=$(echo "$REDIRECT_URL" | sed -n 's/.*\?\(.*\)/\1/p')

echo "Submitting authentication POST request..." | tee -a "$LOG_FILE"
# Most Aruba CloudGuest portals accept a POST with existing params + a 'accept' flag
RESPONSE=$(curl -k -L -v -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -d "${QUERY_PARAMS}&accept=true" -X POST "$ACTION_URL" 2>&1)
echo "HTTP Submission Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
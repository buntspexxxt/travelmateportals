#!/bin/sh
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting H&M Free WiFi authentication process" | tee -a "$LOG_FILE"

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

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -w "%{url_effective}" -A "$USER_AGENT" -o /dev/null -s -m 15 "http://neverssl.com" | tr -d '\015')

echo "Downloading landing page..." | tee -a "$LOG_FILE"
curl -k -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -m 15 "$REDIRECT_URL" -o "$HTML_FILE"

# Extract the meta-refresh or JS redirect URL provided in the new page
NEW_URL=$(sed -n 's/.*URL=\([^"]*\).*/\1/p' "$HTML_FILE" | head -n 1 | tr -d '\015')
echo "Following redirect to: $NEW_URL" | tee -a "$LOG_FILE"

echo "Accessing login portal..." | tee -a "$LOG_FILE"
curl -k -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -m 15 "$NEW_URL" -o "$HTML_FILE"

# Attempt to auto-submit the login form if present
FORM_ACTION=$(sed -n 's/.*action="\([^"]*\)".*/\1/p' "$HTML_FILE" | head -n 1)
if [ -n "$FORM_ACTION" ]; then
    echo "Found form action: $FORM_ACTION. Submitting..." | tee -a "$LOG_FILE"
    curl -k -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -X POST "$FORM_ACTION" -d "accept=true&submit=Accept" -m 15 -v 2>&1 | tee -a "$LOG_FILE"
fi

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/bash
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}" "${HEADERS_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies.txt"
HTML_FILE="/tmp/portal_page.html"

echo "Starting ALDI WiFi Multi-Stage Login..." | tee -a "$LOG_FILE"

# Network Wait
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
done

# Stage 1: Detection
REDIRECT_URL=$(curl -m 15 -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null -w "%{redirect_url}" http://neverssl.com)
if [ -z "$REDIRECT_URL" ]; then
    REDIRECT_URL=$(curl -m 15 -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null -w "%{redirect_url}" http://detectportal.firefox.com/success.txt)
fi

HOST_PORTAL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
PATH_PORTAL=$(echo "$REDIRECT_URL" | cut -d'/' -f4-5)
SPLASH_BASE="${HOST_PORTAL}/${PATH_PORTAL}/"

# Stage 2: Load Page and extract grant URL
echo "Fetching portal landing page..." | tee -a "$LOG_FILE"
curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$REDIRECT_URL" -o "$HTML_FILE"

# Extract the specific button link from the HTML
GRANT_URL=$(sed -n 's/.*class="button" href="\([^"]*\)".*/\1/p' "$HTML_FILE" | head -n 1 | tr -d '\015')

if [ -z "$GRANT_URL" ]; then
    echo "Error: Could not find grant URL. Trying fallback structure..." | tee -a "$LOG_FILE"
    GRANT_URL="${SPLASH_BASE}grant?continue_url=https%3A%2F%2Fwww.aldi-sued.de"
fi

echo "Submitting Login Request to: $GRANT_URL" | tee -a "$LOG_FILE"
curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -H "Referer: $REDIRECT_URL" "$GRANT_URL" > /dev/null

# Stage 3: Verification
echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: No internet (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
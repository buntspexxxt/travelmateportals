#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies.txt"

echo "Starting ALDI WiFi Login Script..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Detecting captive portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null -w "%{redirect_url}" http://neverssl.com)

if [ -z "$REDIRECT_URL" ]; then
    echo "Failed to detect redirect, trying secondary check..." | tee -a "$LOG_FILE"
    REDIRECT_URL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null -w "%{redirect_url}" http://detectportal.firefox.com/success.txt)
fi

if [ -z "$REDIRECT_URL" ]; then
    echo "CRITICAL: Could not detect captive portal redirect URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Captive portal redirect detected: $REDIRECT_URL" | tee -a "$LOG_FILE"

HOST_PORTAL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
PATH_PORTAL=$(echo "$REDIRECT_URL" | cut -d'/' -f4-5)
SPLASH_BASE="${HOST_PORTAL}/${PATH_PORTAL}/"
echo "Dynamic Splash Base: $SPLASH_BASE" | tee -a "$LOG_FILE"

echo "Fetching main page to get initial cookies..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$REDIRECT_URL" > /dev/null

echo "Performing AJAX HEAD request to authorize session and get Continue-Url..." | tee -a "$LOG_FILE"
HEADERS_FILE=$(mktemp)
curl -k -v -A "$USER_AGENT" -I -H "X-Requested-With: XMLHttpRequest" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$REDIRECT_URL" > "$HEADERS_FILE" 2>&1

echo "HEAD Response Headers:" | tee -a "$LOG_FILE"
cat "$HEADERS_FILE" | tee -a "$LOG_FILE"

CONTINUE_HEADER=$(grep -i "^Continue-Url:" "$HEADERS_FILE" | sed 's/.*:[[:space:]]*//' | sed 's/\r//g')
rm -f "$HEADERS_FILE"

if [ -z "$CONTINUE_HEADER" ]; then
    echo "Warning: Continue-Url header not found in HEAD response. Parsing from redirect URL..." | tee -a "$LOG_FILE"
    CONTINUE_HEADER=$(echo "$REDIRECT_URL" | sed -n 's/.*continue_url=\([^&]*\).*/\1/p')
    if [ -z "$CONTINUE_HEADER" ]; then
        CONTINUE_HEADER="https%3A%2F%2Fwww.aldi-sued.de"
    fi
fi

echo "Extracted Continue-Url: $CONTINUE_HEADER" | tee -a "$LOG_FILE"

# URL encode Continue-Url if it isn't already encoded
if echo "$CONTINUE_HEADER" | grep -q "%"; then
    ENCODED_CONTINUE="$CONTINUE_HEADER"
else
    echo "Encoding Continue-Url..." | tee -a "$LOG_FILE"
    ENCODED_CONTINUE=$(echo "$CONTINUE_HEADER" | sed 's/:/%3A/g; s/\//%2F/g; s/?/%3F/g; s/=/%3D/g; s/&/%26/g')
fi

GRANT_URL="${SPLASH_BASE}grant?continue_url=${ENCODED_CONTINUE}"
echo "Executing Grant Request: $GRANT_URL" | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -H "Referer: $REDIRECT_URL" "$GRANT_URL"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_log.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)

echo "Starting 'The Cloud' portal authentication..." | tee -a "$LOG_FILE"

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

echo "Fetching initial splash page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" -w "%{url_effective}" "http://neverssl.com" 2>&1 | grep -E 'Location:|URL:' | tail -n 1 | sed 's/.*: //')

# Extract the base URL
BASE_URL=$(echo "$EFFECTIVE_URL" | cut -d'/' -f1-3)
echo "Detected portal base: $BASE_URL" | tee -a "$LOG_FILE"

echo "Extracting 'Get Online' action URL..." | tee -a "$LOG_FILE"
# The HTML shows a link to /service-platform/url/20347 for 'Get Online'
ACTION_PATH=$(grep -o '/service-platform/url/[0-9]*' "$HTML_FILE" | head -n 1 | tr -d '\015')

if [ -z "$ACTION_PATH" ]; then
    echo "Failed to extract action URL!" | tee -a "$LOG_FILE"
    exit 1
fi

FULL_ACTION_URL="${BASE_URL}${ACTION_PATH}"
echo "Navigating to action URL: $FULL_ACTION_URL" | tee -a "$LOG_FILE"

# Follow the flow to trigger the session activation
RESPONSE_CODE=$(curl -k -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" "$FULL_ACTION_URL")
echo "HTTP Action Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

# Verify internet connectivity
echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
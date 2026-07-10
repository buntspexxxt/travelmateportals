#!/bin/bash
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_OUT:-}"' EXIT
LOG_FILE="/tmp/portal_log.txt"
echo "Starting The Cloud portal login sequence..." | tee -a "$LOG_FILE"

echo "Waiting for network..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

echo "Fetching portal index..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -L -c "$COOKIE_FILE" -o "$HTML_OUT" "http://neverssl.com" >/dev/null 2>&1

# The Cloud v5 uses a registration form that usually requires accepting Terms. 
# Extracting action URL and confirming current state.
HTML=$(cat "$HTML_OUT")
ACTION_URL=$(echo "$HTML" | sed -n 's/.*id="registration" method="POST" action="\([^"]*\)".*/\1/p')

if [ -z "$ACTION_URL" ]; then
    echo "Could not find registration form action URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting acceptance POST to $ACTION_URL..." | tee -a "$LOG_FILE"
# Sending empty payload as portal is 'one-click' acceptance based on existing session cookie
RESPONSE_CODE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -w "%{http_code}" -o /dev/null -d "tos=true" "$ACTION_URL")

echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal failed. HTTP Check: $CHECK_CODE"
    exit 1
fi
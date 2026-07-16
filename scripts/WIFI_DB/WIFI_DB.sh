#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_log.txt"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Starting script..." | tee -a "$LOG_FILE"

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

echo "Checking if we are already online..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -o /dev/null -w "%{http_code}" -m 10 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ]; then
    echo "Already online." | tee -a "$LOG_FILE"
    exit 0
fi

echo "Portal detected, attempting to reach the auth controller..." | tee -a "$LOG_FILE"
# The logs indicate potential issues with wifi_bahn_de and hotsplots. We attempt to follow the standard DB redirect flow.
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%{url_effective}" -o /dev/null -m 15 "http://neverssl.com" 2>>"$LOG_FILE" | sed "s/\r//g")

echo "Redirected to: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Attempting a generic trigger for the DB/Hotsplots portal login flow
# Most DB portals use a POST to an action URL found in the login page
HTML_OUT=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -c "$COOKIE_FILE" -m 15 "$EFFECTIVE_URL" 2>>"$LOG_FILE")

# If a form exists with a login button, extract action and submit empty fields
ACTION_URL=$(echo "$HTML_OUT" | sed -n 's/.*action="\([^"]*\)".*/\1/p' | head -n 1)

if [ -n "$ACTION_URL" ]; then
    echo "Found login form at $ACTION_URL, submitting..." | tee -a "$LOG_FILE"
    curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "" "$ACTION_URL" >> "$LOG_FILE" 2>&1
fi

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

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1
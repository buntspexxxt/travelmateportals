#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_FILE"' EXIT

echo "Starting Telekom Hotspot login flow..." | tee -a "$LOG_FILE"

# Wait for network
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
    i=$((i + 1))
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Step 1: Fetching initial redirect..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -w "%\{url_effective\}" -o "$HTML_FILE" -m 15 "http://neverssl.com")

echo "Step 2: Submitting initial login POST..." | tee -a "$LOG_FILE"
# Using empty credentials for free/agree-only portals
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -d "UserName=&Password=&FNAME=0&button=Login&OriginatingServer=http%3A%2F%2Fneverssl.com%2F" \
    -m 20 "$EFFECTIVE_URL")

echo "Step 3: Checking if another interaction is needed (e.g. Terms)..." | tee -a "$LOG_FILE"
# Look for a secondary URL or token if the portal presents a multi-step form
# This logic attempts a follow-up request if the first didn't return internet access

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal sequence failed or requires manual interaction." | tee -a "$LOG_FILE"
exit 1
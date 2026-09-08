#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
echo "Starting Vodafone Hotspot login process..." | tee -a "$LOG_FILE"

# Cleanup on exit
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

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

# Fetch initial redirect parameters
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
echo "Fetching redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -w "%{url_effective}" -o /dev/null -A "$USER_AGENT" "http://neverssl.com")
SID=$(echo "$REDIRECT_URL" | sed -n 's/.*sid=\([^&]*\).*/\1/p')

if [ -z "$SID" ]; then
    echo "Failed to extract SID from URL: $REDIRECT_URL" | tee -a "$LOG_FILE"
    exit 1
fi
echo "Extracted SID: $SID" | tee -a "$LOG_FILE"

# Get session API
API_DOMAIN="hotspot.vodafone.de"
echo "Requesting session data..." | tee -a "$LOG_FILE"
SESSION_JSON=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 "https://$API_DOMAIN/api/v4/session?sid=$SID")
echo "HTTP Response: $?" | tee -a "$LOG_FILE"

SESSION=$(echo "$SESSION_JSON" | sed -n 's/.*"session":"\([^"]*\)".*/\1/p')
if [ -z "$SESSION" ]; then
    echo "Failed to extract session token." | tee -a "$LOG_FILE"
    exit 1
fi

# Accept terms if required by logic
echo "Performing final login..." | tee -a "$LOG_FILE"
# Note: As per portal logic, if username/pass are empty, we aim for guest/free access or session resumption.
LOGIN_RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 -d "session=$SESSION" "https://$API_DOMAIN/api/v4/login?sid=$SID")

echo "Login response: $LOGIN_RESPONSE" | tee -a "$LOG_FILE"

# Verify internet
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
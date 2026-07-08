#!/bin/bash
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Waiting for network..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then break; fi
    sleep 2
done

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -v -A "$USER_AGENT" -o /dev/null -w "%{redirect_url}" "http://connectivitycheck.gstatic.com/generate_204" 2>&1 | grep "Location:" | sed 's/.*Location: //g' | sed 's/\\r//g')
HOST=$(echo "$REDIRECT_URL" | cut -d/ -f1-3)

echo "Performing initial session resume..." | tee -a "$LOG_FILE"
# Extract query params from redirect to resume
QUERY=$(echo "$REDIRECT_URL" | sed -n 's/.*?\(.*\)/\1/p')
SESSION_URL="$HOST/cp/session/resume?$QUERY"

SESSION_DATA=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$SESSION_URL")
echo "Session Response: $SESSION_DATA" | tee -a "$LOG_FILE"

# The portal logic uses a resume/login flow. We construct the login request.
# Peplink portals often require a specific login hit if the initial resume returns a session object.
echo "Submitting Login Request..." | tee -a "$LOG_FILE"
LOGIN_URL="$HOST/cp/login?resume=true&command=login&lang=en&$QUERY&_=$(date +%s)"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LOGIN_URL"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Connectivity check failed (Code: $CHECK_CODE)"
    exit 1
fi
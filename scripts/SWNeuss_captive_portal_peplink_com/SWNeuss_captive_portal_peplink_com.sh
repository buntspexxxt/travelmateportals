#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/120.0.0.0"

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
    i=$((i + 1))
done

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o /dev/null -A "$USER_AGENT" "http://neverssl.com")
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*\?\(.*\)/\1/p')
API_HOST=$(echo "$EFFECTIVE_URL" | awk -F/ '{print $3}')

echo "Resuming session via Peplink API..." | tee -a "$LOG_FILE"
RESUME_URL="https://guest7.ic.peplink.com/cp/session/resume?$QUERY_STRING"
RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 "$RESUME_URL")

echo "Checking if interaction required..." | tee -a "$LOG_FILE"
if echo "$RESPONSE" | grep -q '"is_prompt_sign_in":true'; then
    echo "Manual connect button interaction required." | tee -a "$LOG_FILE"
    LOGIN_URL="https://guest7.ic.peplink.com/cp/login?$QUERY_STRING&command=login&resume=true"
    curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -o /dev/null -m 15 "$LOGIN_URL"
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
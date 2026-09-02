#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting multi-stage Peplink portal login..." > "$LOG_FILE"

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

COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Stage 1: Fetching initial redirect parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" -w "%{url_effective}" -o /dev/null -m 15 "http://neverssl.com" 2>> "$LOG_FILE" | tr -d '\015')
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*\?\(.*\)/\1/p')

echo "Stage 2: Attempting session resume..." | tee -a "$LOG_FILE"
# Using the parameters from the initial redirect for the resume call
RESUME_URL="https://guest7.ic.peplink.com/cp/session/resume?$QUERY_STRING"
RESUME_OUT=$(curl -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -m 15 "$RESUME_URL" 2>> "$LOG_FILE")
echo "Resume Status: $RESUME_OUT" | tee -a "$LOG_FILE"

echo "Stage 3: Submitting final login trigger..." | tee -a "$LOG_FILE"
# Based on analysis, the portal requires a POST or GET request to the login endpoint using the session parameters
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?$QUERY_STRING&command=login&resume=true&lang=en"
CURL_OUT=$(curl -k -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -m 15 "$LOGIN_URL" 2>> "$LOG_FILE")

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
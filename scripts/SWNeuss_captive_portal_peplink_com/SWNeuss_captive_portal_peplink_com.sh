#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting Enhanced Peplink Captive Portal Login" | tee -a "$LOG_FILE"

# 1. Wait for Network
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 2. Extract Session/Resume Data
echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
# Using -I to just fetch headers, capturing the redirect URL
REDIRECT_RESP=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt http://detectportal.firefox.com/success.txt 2>&1)
REDIRECT_URL=$(echo "$REDIRECT_RESP" | sed -n 's/.*Location: //p' | tr -d '\r')
QUERY_STRING=$(echo "$REDIRECT_URL" | cut -d'?' -f2)
echo "Query String: $QUERY_STRING" | tee -a "$LOG_FILE"

# 3. Resume Session
echo "Querying session/resume API..." | tee -a "$LOG_FILE"
API_URL="https://guest7.ic.peplink.com/cp/session/resume?$QUERY_STRING"
# Fetch session resume data to see if we need a user interaction
API_RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt "$API_URL")
echo "API Response: $API_RESPONSE" | tee -a "$LOG_FILE"

# 4. Handle Login Logic
# The portal logic shows that if the session is not resumed or requires a connect button, we hit /cp/login
# We build the login request with the parameters extracted earlier
echo "Sending login command..." | tee -a "$LOG_FILE"
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?$QUERY_STRING&command=login"
FINAL_RESPONSE=$(curl -v -L -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt "$LOGIN_URL")
echo "Final Action HTTP Response: $?" | tee -a "$LOG_FILE"

# 5. Smart Wait
echo "Waiting for session activation..." | tee -a "$LOG_FILE"
sleep 10

# 6. Verify connectivity
echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet reached." | tee -a "$LOG_FILE" && exit 0 || exit 1
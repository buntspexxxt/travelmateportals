#!/bin/bash
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE="/tmp/portal_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Accessing initial trigger to find portal redirect..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o /dev/null -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://neverssl.com")

echo "Detected portal redirect to: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Fetching portal login page..." | tee -a "$LOG_FILE"
HTML=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$EFFECTIVE_URL")

echo "Extracting form action and hidden fields..." | tee -a "$LOG_FILE"
FORM_ACTION=$(echo "$HTML" | sed -n 's/.*<form[^>]*action="\([^"]*\)".*/\1/p' | head -n 1)
# If action is relative, handle it
if [[ "$FORM_ACTION" == /* ]]; then
    BASE_URL=$(echo "$EFFECTIVE_URL" | cut -d/ -f1-3)
    FORM_ACTION="${BASE_URL}${FORM_ACTION}"
fi

echo "Submitting portal login form..." | tee -a "$LOG_FILE"
# Using POST with empty credentials as per instructions for free portal
curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -d "username=&password=&accept=true" "$FORM_ACTION" > /tmp/auth_response.html 2>&1

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." | tee -a "$LOG_FILE"

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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)

echo "Fetching redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -w "%{url_effective}" -o /dev/null -A "$USER_AGENT" -m 15 "http://neverssl.com")
REDIRECT_URL=$(echo "$REDIRECT_URL" | tr -d '\015')
echo "Effective URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

QUERY_STRING=$(echo "$REDIRECT_URL" | sed -n 's/^[^?]*?\(.*\)/\1/p')
HOST_BASE=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)

echo "Submitting session resume request..." | tee -a "$LOG_FILE"
# Extract base domain to construct session API URL
SESSION_API="${HOST_BASE}/cp/session/resume"
echo "API Endpoint: $SESSION_API" | tee -a "$LOG_FILE"

RESPONSE=$(curl -k -v -A "$USER_AGENT" -m 15 -c "$COOKIE_FILE" -b "$COOKIE_FILE" -G -d "$QUERY_STRING" "$SESSION_API")
echo "Response received." | tee -a "$LOG_FILE"

echo "Attempting to trigger login command..." | tee -a "$LOG_FILE"
LOGIN_URL="${HOST_BASE}/cp/login"
curl -k -v -A "$USER_AGENT" -m 15 -c "$COOKIE_FILE" -b "$COOKIE_FILE" -G -d "$QUERY_STRING" -d "command=login" "$LOGIN_URL" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
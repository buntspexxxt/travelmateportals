#!/bin/sh

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
echo "Starting multi-stage Peplink login script..." | tee -a "$LOG_FILE"

# Network check
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

# Get initial redirect and extract dynamic parameters from URL
echo "Fetching redirect URL..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o /dev/null -A "$USER_AGENT" -m 15 "http://neverssl.com")
EFFECTIVE_URL=$(echo "$EFFECTIVE_URL" | tr -d '\015')
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/^[^?]*?\(.*\)/\1/p')
HOST_BASE=$(echo "$EFFECTIVE_URL" | cut -d'/' -f1-3)

# Stage 1: Attempt to resume session
echo "Stage 1: Attempting to resume session via API..." | tee -a "$LOG_FILE"
API_URL="${HOST_BASE}/cp/session/resume"
JSON_RESPONSE=$(curl -k -A "$USER_AGENT" -m 15 -c "$COOKIE_FILE" -b "$COOKIE_FILE" -G -d "$QUERY_STRING" "$API_URL")
echo "API Response: $JSON_RESPONSE" | tee -a "$LOG_FILE"

# Stage 2: Login
# The JS logic indicates the final action is a GET/POST to /cp/login with the query parameters
echo "Stage 2: Submitting final login request..." | tee -a "$LOG_FILE"
LOGIN_URL="${HOST_BASE}/cp/login"
curl -k -v -A "$USER_AGENT" -m 15 -c "$COOKIE_FILE" -b "$COOKIE_FILE" -G -d "$QUERY_STRING" -d "command=login" "$LOGIN_URL" >> "$LOG_FILE" 2>&1

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
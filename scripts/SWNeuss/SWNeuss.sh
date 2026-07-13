# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
#!/bin/sh
# SCRIPT_VERSION="1.1.0"
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
REDIRECT_URL=$(curl -k -L -w "%{redirect_url}" -o /dev/null -A "$USER_AGENT" -m 15 "http://neverssl.com")
REDIRECT_URL=$(echo "$REDIRECT_URL" | tr -d '\015')

if [ -z "$REDIRECT_URL" ] || [ "$REDIRECT_URL" = "http://neverssl.com/" ]; then
    echo "Direct neverssl.com redirect failed or returned same URL. Trying default gateway..." | tee -a "$LOG_FILE"
    GW_IP=$(ip route | grep default | awk '{print $3}')
    if [ -n "$GW_IP" ]; then
        echo "Detected Gateway IP: $GW_IP. Attempting to fetch redirect..." | tee -a "$LOG_FILE"
        REDIRECT_URL=$(curl -k -L -w "%{redirect_url}" -o /dev/null -A "$USER_AGENT" -m 15 "http://$GW_IP")
        REDIRECT_URL=$(echo "$REDIRECT_URL" | tr -d '\015')
    fi
fi

if [ -z "$REDIRECT_URL" ]; then
    echo "ERROR: Failed to retrieve redirect URL from both neverssl.com and Gateway." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Effective URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

QUERY_STRING=$(echo "$REDIRECT_URL" | sed -n 's/^[^?]*?\(.*\)/\1/p')
HOST_BASE=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)

echo "Submitting session resume request..." | tee -a "$LOG_FILE"
SESSION_API="${HOST_BASE}/cp/session/resume"
echo "API Endpoint: $SESSION_API" | tee -a "$LOG_FILE"

RESUME_RESP=$(curl -k -v -A "$USER_AGENT" -m 15 -c "$COOKIE_FILE" -b "$COOKIE_FILE" -G -d "$QUERY_STRING" "$SESSION_API")
echo "Resume Response: $RESUME_RESP" | tee -a "$LOG_FILE"

echo "Extracting session parameters from resume response..." | tee -a "$LOG_FILE"
ACCESS_MODE=$(echo "$RESUME_RESP" | sed -n 's/.*"access_mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
USERNAME=$(echo "$RESUME_RESP" | sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
MARKET_OPT_IN=$(echo "$RESUME_RESP" | sed -n 's/.*"market_opt_in"[[:space:]]*:[[:space:]]*\([truefalsenull]*\).*/\1/p')
AUTO_SIGN_IN_EXPIRED=$(echo "$RESUME_RESP" | sed -n 's/.*"is_auto_sign_in_expired"[[:space:]]*:[[:space:]]*\([truefalsenull]*\).*/\1/p')

echo "Attempting to trigger login command..." | tee -a "$LOG_FILE"
LOGIN_URL="${HOST_BASE}/cp/login"

LOGIN_PARAMS="${QUERY_STRING}&command=login&resume=true"
[ -n "$ACCESS_MODE" ] && [ "$ACCESS_MODE" != "null" ] && LOGIN_PARAMS="${LOGIN_PARAMS}&access_mode=${ACCESS_MODE}"
[ -n "$USERNAME" ] && [ "$USERNAME" != "null" ] && LOGIN_PARAMS="${LOGIN_PARAMS}&username=${USERNAME}"
[ -n "$MARKET_OPT_IN" ] && [ "$MARKET_OPT_IN" != "null" ] && LOGIN_PARAMS="${LOGIN_PARAMS}&market_opt_in=${MARKET_OPT_IN}"
[ -n "$AUTO_SIGN_IN_EXPIRED" ] && [ "$AUTO_SIGN_IN_EXPIRED" != "null" ] && LOGIN_PARAMS="${LOGIN_PARAMS}&auto_sign_in_expired=${AUTO_SIGN_IN_EXPIRED}"

echo "Login URL: $LOGIN_URL with params: $LOGIN_PARAMS" | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -m 15 -c "$COOKIE_FILE" -b "$COOKIE_FILE" -G -d "$LOGIN_PARAMS" "$LOGIN_URL" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
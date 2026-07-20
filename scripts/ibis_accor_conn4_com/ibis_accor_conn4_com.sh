#!/bin/sh
# SCRIPT_VERSION="1.3.0"

LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="/tmp/ibis_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

trap 'rm -f "${COOKIE_JAR:-}"' EXIT

echo "Waiting for network readiness..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready!" | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Fetching initial portal redirect..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_JAR" -w "%{url_effective}" -o /dev/null -m 15 "http://neverssl.com")
echo "Base URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Extracting scene configuration..." | tee -a "$LOG_FILE"
HTML_BODY=$(curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 "$EFFECTIVE_URL")
SCENE_PLAYER_URI=$(echo "$HTML_BODY" | sed -n 's/.*"scenePlayerUri":"\([^"]*\)".*/\1/p')
SCENE_PLAYER_URL="https://accor.conn4.com${SCENE_PLAYER_URI}"

echo "Fetching player token..." | tee -a "$LOG_FILE"
PLAYER_BODY=$(curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 "$SCENE_PLAYER_URL")
TOKEN=$(echo "$PLAYER_BODY" | sed -n 's/.*"token":"\([^" ]*\)".*/\1/p')

echo "Creating session..." | tee -a "$LOG_FILE"
SESSION_RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 -X POST --data-urlencode "authorization=token=${TOKEN}" "https://accor.conn4.com/wbs/api/v1/create-session/")
SESSION_ID=$(echo "$SESSION_RESPONSE" | sed -n 's/.*"session":"\([^" ]*\)".*/\1/p')

echo "Finalizing registration..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -m 15 -X POST --data-urlencode "authorization=session=${SESSION_ID}" --data-urlencode "registration_type=terms-only" --data-urlencode "registration[terms]=1" "https://accor.conn4.com/wbs/api/v1/register/free/"

echo "Verifying internet connectivity (polling 40s)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Checking..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done
echo "ERROR: No connectivity after 40 seconds." | tee -a "$LOG_FILE"
exit 1
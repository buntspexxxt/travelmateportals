#!/bin/bash
# SCRIPT_VERSION="1.1.0"
trap 'rm -f "${COOKIE_JAR:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_JAR="/tmp/ibis_cookies.txt"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

rm -f "$COOKIE_JAR"
echo "Fetching landing page..." | tee -a "$LOG_FILE"
# Get initial redirect headers and save cookies
curl -v -k -c "$COOKIE_JAR" -A "$USER_AGENT" "http://neverssl.com" > /dev/null 2>&1

# The portal requires interaction with the WBS API
BASE_URL="https://accor.conn4.com"

echo "Fetching main config..." | tee -a "$LOG_FILE"
HTML_BODY=$(curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$BASE_URL")
SCENE_PLAYER_URI=$(echo "$HTML_BODY" | sed -n 's/.*"scenePlayerUri":"\([^"\\]*\)".*/\1/p')
SCENE_PLAYER_URL="${BASE_URL}${SCENE_PLAYER_URI}"

echo "Fetching player data..." | tee -a "$LOG_FILE"
PLAYER_BODY=$(curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$SCENE_PLAYER_URL")
TOKEN=$(echo "$PLAYER_BODY" | sed -n 's/.*"token":"\([^" ]*\)".*/\1/p')

echo "Creating session..." | tee -a "$LOG_FILE"
SESSION_RESPONSE=$(curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" -X POST -d "authorization=token%3D${TOKEN}" "${BASE_URL}/wbs/api/v1/create-session/")
SESSION_ID=$(echo "$SESSION_RESPONSE" | sed -n 's/.*"session":"\([^" ]*\)".*/\1/p')

echo "Finalizing registration..." | tee -a "$LOG_FILE"
# Using terms-only as standard for ibis guest wifi
curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" -X POST -d "authorization=session%3D${SESSION_ID}&registration_type=terms-only&registration%5Bterms%5D=1" "${BASE_URL}/wbs/api/v1/register/free/"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
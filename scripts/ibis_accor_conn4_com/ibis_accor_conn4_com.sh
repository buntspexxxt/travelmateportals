#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"
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

# Trigger initial flow
echo "Triggering portal flow..." | tee -a "$LOG_FILE"
REDIRECT_INFO=$(curl -v -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "http://neverssl.com" 2>&1)
PORTAL_URL=$(echo "$REDIRECT_INFO" | sed -n 's/.*[Ll]ocation: //p' | sed 's/\r//g' | head -n 1)
[ -z "$PORTAL_URL" ] && PORTAL_URL="https://accor.conn4.com/"

echo "Fetching main config..." | tee -a "$LOG_FILE"
HTML_BODY=$(curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$PORTAL_URL")
SCENE_PLAYER_URI=$(echo "$HTML_BODY" | sed -n 's/.*"scenePlayerUri":"\([^"\\]*\)".*/\1/p')
SCENE_PLAYER_URL="https://accor.conn4.com${SCENE_PLAYER_URI}"

PLAYER_BODY=$(curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$SCENE_PLAYER_URL")
TOKEN=$(echo "$PLAYER_BODY" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
SCENE_ID=$(echo "$PLAYER_BODY" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

echo "Creating session..." | tee -a "$LOG_FILE"
SESSION_RESPONSE=$(curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" -X POST -d "session_id=&with-tariffs=1&locale=de_DE&authorization=token%3D${TOKEN}" "https://accor.conn4.com/wbs/api/v1/create-session/")
SESSION_ID=$(echo "$SESSION_RESPONSE" | sed -n 's/.*"session":"\([^"]*\)".*/\1/p')

echo "Registering free access..." | tee -a "$LOG_FILE"
# Using registration_type=free-wifi or generic terms-only based on the hint: "24-Stunden-Pass"
# The portal expects standard free registration.
curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" -X POST -d "authorization=session%3D${SESSION_ID}&registration_type=terms-only&registration%5Bterms%5D=1" "https://accor.conn4.com/wbs/api/v1/register/free/"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/bash
# SCRIPT_VERSION="1.3.0"
trap 'rm -f "${COOKIE_JAR:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_JAR="/tmp/ibis_cookies.txt"

# Wait for network
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

echo "Step 1: Fetching initial landing page redirect from neverssl.com..." | tee -a "$LOG_FILE"
# Do not use silent, capture headers and redirection
RESPONSE=$(curl -v -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "http://neverssl.com" 2>&1)

# Safely extract Location header, removing carriage returns
PORTAL_URL=$(echo "$RESPONSE" | grep -i 'Location:' | head -n 1 | sed 's/.*[Ll]ocation: //g' | sed 's/\r//g' | sed 's/ //g')

if [ -z "$PORTAL_URL" ]; then
    echo "No redirect Location header found. Trying fallback portal URL..." | tee -a "$LOG_FILE"
    PORTAL_URL="https://accor.conn4.com/"
else
    echo "Redirected to: $PORTAL_URL" | tee -a "$LOG_FILE"
fi

echo "Step 2: Fetching portal main page..." | tee -a "$LOG_FILE"
HTML_BODY=$(curl -v -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$PORTAL_URL" 2>&1)

# Dynamically extract base host from the PORTAL_URL or fallback
BASE_HOST=$(echo "$PORTAL_URL" | sed -n 's/\(https*:\/\/[^\/]*\).*/\1/p')
if [ -z "$BASE_HOST" ]; then
    BASE_HOST="https://accor.conn4.com"
fi
echo "Base host determined as: $BASE_HOST" | tee -a "$LOG_FILE"

# Extract scenePlayerUri robustly (removing backslashes)
echo "Step 3: Extracting scene player URI..." | tee -a "$LOG_FILE"
SCENE_PLAYER_URI=$(echo "$HTML_BODY" | sed -n 's/.*"scenePlayerUri":"\([^"\]*\(\\\/[^"\]*\)*\)".*/\1/p' | sed 's/\\//g')

if [ -z "$SCENE_PLAYER_URI" ]; then
    # Fallback pattern if previous extraction failed
    SCENE_PLAYER_URI=$(echo "$HTML_BODY" | sed -n 's/.*"scenePlayerUri":"\([^"]*\)".*/\1/p' | sed 's/\\//g')
fi

if [ -z "$SCENE_PLAYER_URI" ]; then
    echo "ERROR: Could not find scenePlayerUri in the landing page!" | tee -a "$LOG_FILE"
    exit 1
fi

SCENE_PLAYER_URL="${BASE_HOST}${SCENE_PLAYER_URI}"
echo "Scene Player URL: $SCENE_PLAYER_URL" | tee -a "$LOG_FILE"

echo "Step 4: Fetching player data for token extraction..." | tee -a "$LOG_FILE"
PLAYER_BODY=$(curl -v -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$SCENE_PLAYER_URL" 2>&1)

TOKEN=$(echo "$PLAYER_BODY" | sed -n 's/.*"token":"\([^" ]*\)".*/\1/p')
if [ -z "$TOKEN" ]; then
    # Try extracting from HTML_BODY or cookies if not found in player data
    TOKEN=$(echo "$HTML_BODY" | sed -n 's/.*"token":"\([^" ]*\)".*/\1/p')
fi

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to extract authorization token!" | tee -a "$LOG_FILE"
    exit 1
fi
echo "Extracted Token: $TOKEN" | tee -a "$LOG_FILE"

echo "Step 5: Creating Session..." | tee -a "$LOG_FILE"
SESSION_RESPONSE=$(curl -v -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "authorization=token%3D${TOKEN}" \
    "${BASE_HOST}/wbs/api/v1/create-session/")

echo "Session Response: $SESSION_RESPONSE" | tee -a "$LOG_FILE"
SESSION_ID=$(echo "$SESSION_RESPONSE" | sed -n 's/.*"session":"\([^" ]*\)".*/\1/p')

if [ -z "$SESSION_ID" ]; then
    echo "ERROR: Failed to retrieve Session ID from session creation!" | tee -a "$LOG_FILE"
    exit 1
fi
echo "Extracted Session ID: $SESSION_ID" | tee -a "$LOG_FILE"

echo "Step 6: Registering free access / accepting terms..." | tee -a "$LOG_FILE"
REGISTRATION_RESPONSE=$(curl -v -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "authorization=session%3D${SESSION_ID}&registration_type=terms-only&registration%5Bterms%5D=1" \
    "${BASE_HOST}/wbs/api/v1/register/free/")

echo "Registration Response: $REGISTRATION_RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi

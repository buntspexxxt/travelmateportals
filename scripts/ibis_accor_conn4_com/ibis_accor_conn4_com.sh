#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_JAR="/tmp/ibis_cookies.txt"

echo "Starting Ibis/m3connect Captive Portal Login..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP (IP & Gateway)
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# 2. Trigger initial redirect
echo "Fetching redirect page from neverssl.com..." | tee -a "$LOG_FILE"
rm -f "$COOKIE_JAR"
RESPONSE=$(curl -v -L -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
     --connect-timeout 10 \
     -A "$USER_AGENT" \
     "http://neverssl.com" 2>&1)

# Extract effective URL
EFFECTIVE_URL=$(echo "$RESPONSE" | grep -i "< Location:" | tail -n 1 | sed -n "s/.*Location: //p" | tr -d '\r')
if [ -z "$EFFECTIVE_URL" ]; then
    HTML_BODY=$(curl -s -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "http://neverssl.com")
else
    echo "Redirected to: $EFFECTIVE_URL" | tee -a "$LOG_FILE"
    HTML_BODY=$(curl -s -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$EFFECTIVE_URL")
fi

# Extract scenePlayerUri from __sceneConfig in the HTML body
SCENE_PLAYER_URI=$(echo "$HTML_BODY" | sed -n 's/.*"scenePlayerUri":"\([^"\]*\)".*/\1/p' | sed 's/\//g')
if [ -z "$SCENE_PLAYER_URI" ]; then
    # Try alternative matching
    SCENE_PLAYER_URI=$(echo "$HTML_BODY" | grep -oE '"scenePlayerUri":"[^"]+"' | cut -d'"' -f4 | sed 's/\//g')
fi
echo "Extracted scenePlayerUri: $SCENE_PLAYER_URI" | tee -a "$LOG_FILE"

if [ -z "$SCENE_PLAYER_URI" ]; then
    echo "Error: Could not extract scenePlayerUri. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

SCENE_PLAYER_URL="https://accor.conn4.com${SCENE_PLAYER_URI}"
echo "Fetching Scene Player: $SCENE_PLAYER_URL" | tee -a "$LOG_FILE"

PLAYER_BODY=$(curl -s -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$SCENE_PLAYER_URL")

# Extract token and id from player body JSON
TOKEN=$(echo "$PLAYER_BODY" | sed -n 's/.*"token":"\([^"/]*\)".*/\1/p')
SCENE_ID=$(echo "$PLAYER_BODY" | sed -n 's/.*"id":"\([^"/]*\)".*/\1/p')

echo "Extracted Token: $TOKEN" | tee -a "$LOG_FILE"
echo "Extracted Scene ID: $SCENE_ID" | tee -a "$LOG_FILE"

if [ -z "$TOKEN" ] || [ -z "$SCENE_ID" ]; then
    echo "Error: Could not extract Token or Scene ID. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

SCENE_URL="https://accor.conn4.com/scenes/${SCENE_ID}/"
echo "Initializing scene URL: $SCENE_URL" | tee -a "$LOG_FILE"
curl -s -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" -H "Referer: $SCENE_PLAYER_URL" "$SCENE_URL" > /dev/null

# 3. Create Session POST
echo "Creating session..." | tee -a "$LOG_FILE"
SESSION_RESPONSE=$(curl -s -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" \
    -X POST \
    -H "Referer: $SCENE_URL" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Origin: https://accor.conn4.com" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    -d "session_id=&with-tariffs=1&locale=de_DE&authorization=token%3D${TOKEN}" \
    "https://accor.conn4.com/wbs/api/v1/create-session/")

# Extract session id from response
SESSION_ID=$(echo "$SESSION_RESPONSE" | sed -n 's/.*"session":"\([^"/]*\)".*/\1/p')
echo "Created Session ID: $SESSION_ID" | tee -a "$LOG_FILE"

if [ -z "$SESSION_ID" ]; then
    SESSION_ID=$(echo "$SESSION_RESPONSE" | grep -oE '"session":"[^"]+"' | cut -d'"' -f4)
fi

if [ -z "$SESSION_ID" ]; then
    echo "Error: Could not create session. Response: $SESSION_RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi

# 4. Register Free Session POST
echo "Registering free internet access..." | tee -a "$LOG_FILE"
REGISTER_RESPONSE=$(curl -s -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" \
    -X POST \
    -H "Referer: $SCENE_URL" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Origin: https://accor.conn4.com" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    -d "authorization=session%3D${SESSION_ID}&registration_type=terms-only&registration%5Bterms%5D=1" \
    "https://accor.conn4.com/wbs/api/v1/register/free/")

echo "Registration response: $REGISTER_RESPONSE" | tee -a "$LOG_FILE"

# 5. Connectivity check
echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && { echo "Success: Internet access restored."; rm -f "$COOKIE_JAR"; exit 0; } || { echo "Error: Connectivity test failed."; rm -f "$COOKIE_JAR"; exit 1; }

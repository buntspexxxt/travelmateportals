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

# Clean cookie jar
rm -f "$COOKIE_JAR"

# 2. Trigger initial redirect to capture the gateway ident URL
echo "Step 1: Sending initial request to neverssl.com to trigger redirect..." | tee -a "$LOG_FILE"
HEADERS=$(curl -v -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "http://neverssl.com" 2>&1)

REDIRECT_URL=$(echo "$HEADERS" | grep -i "Location:" | tail -n 1 | sed -n "s/.*[Ll]ocation: //p" | tr -d '\r')

if [ -z "$REDIRECT_URL" ]; then
    echo "No redirect URL found in headers. Let's check if we already have internet..." | tee -a "$LOG_FILE"
    ping -c 3 8.8.8.8 >/dev/null && { echo "Already online! Exiting."; exit 0; }
    echo "Error: Not online and no redirect URL found. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Redirect URL found: $REDIRECT_URL" | tee -a "$LOG_FILE"

# 3. Request the redirect URL to set cookies and get the portal URL
echo "Step 2: Requesting the ident redirect URL to set initial cookies..." | tee -a "$LOG_FILE"
IDENT_HEADERS=$(curl -v -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$REDIRECT_URL" 2>&1)

PORTAL_URL=$(echo "$IDENT_HEADERS" | grep -i "Location:" | tail -n 1 | sed -n "s/.*[Ll]ocation: //p" | tr -d '\r')

if [ -z "$PORTAL_URL" ] || [ "$PORTAL_URL" = "#" ] || [ "$PORTAL_URL" = "https://accor.conn4.com/#" ]; then
    PORTAL_URL="https://accor.conn4.com/"
fi

echo "Portal URL resolved: $PORTAL_URL" | tee -a "$LOG_FILE"

# 4. Fetch the portal landing page HTML
echo "Step 3: Fetching portal landing page HTML..." | tee -a "$LOG_FILE"
HTML_BODY=$(curl -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$PORTAL_URL")

# Extract scenePlayerUri from __sceneConfig in the HTML body
SCENE_PLAYER_URI=$(echo "$HTML_BODY" | sed -n 's/.*"scenePlayerUri":"\([^"]*\)".*/\1/p' | tr -d '\\')

if [ -z "$SCENE_PLAYER_URI" ]; then
    echo "Error: Could not extract scenePlayerUri from HTML. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracted scenePlayerUri: $SCENE_PLAYER_URI" | tee -a "$LOG_FILE"

SCENE_PLAYER_URL="https://accor.conn4.com${SCENE_PLAYER_URI}"
echo "Step 4: Fetching Scene Player configuration from: $SCENE_PLAYER_URL" | tee -a "$LOG_FILE"
PLAYER_BODY=$(curl -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$SCENE_PLAYER_URL")

# Extract token and scene ID from player body JSON
TOKEN=$(echo "$PLAYER_BODY" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
SCENE_ID=$(echo "$PLAYER_BODY" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

echo "Extracted Token: $TOKEN" | tee -a "$LOG_FILE"
echo "Extracted Scene ID: $SCENE_ID" | tee -a "$LOG_FILE"

if [ -z "$TOKEN" ] || [ -z "$SCENE_ID" ]; then
    echo "Error: Could not extract Token or Scene ID from Scene Player. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

# Initialize scene session
SCENE_URL="https://accor.conn4.com/scenes/${SCENE_ID}/"
echo "Step 5: Initializing scene URL: $SCENE_URL" | tee -a "$LOG_FILE"
curl -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" -H "Referer: $SCENE_PLAYER_URL" "$SCENE_URL" > /dev/null

# 5. Create Session POST
echo "Step 6: Creating WBS session..." | tee -a "$LOG_FILE"
SESSION_RESPONSE=$(curl -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" \
    -X POST \
    -H "Referer: $SCENE_URL" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Origin: https://accor.conn4.com" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    -d "session_id=&with-tariffs=1&locale=de_DE&authorization=token%3D${TOKEN}" \
    "https://accor.conn4.com/wbs/api/v1/create-session/")

echo "Create Session Response: $SESSION_RESPONSE" | tee -a "$LOG_FILE"

# Extract session id from response
SESSION_ID=$(echo "$SESSION_RESPONSE" | sed -n 's/.*"session":"\([^"]*\)".*/\1/p')

if [ -z "$SESSION_ID" ]; then
    echo "Error: Could not extract Session ID from create-session response. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Created Session ID: $SESSION_ID" | tee -a "$LOG_FILE"

# 6. Register Free Session POST
echo "Step 7: Registering free internet access..." | tee -a "$LOG_FILE"
REGISTER_RESPONSE=$(curl -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" \
    -X POST \
    -H "Referer: $SCENE_URL" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Origin: https://accor.conn4.com" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    -d "authorization=session%3D${SESSION_ID}&registration_type=terms-only&registration%5Bterms%5D=1" \
    "https://accor.conn4.com/wbs/api/v1/register/free/")

echo "Registration Response: $REGISTER_RESPONSE" | tee -a "$LOG_FILE"

# Quota checking function definition
check_quota() {
    echo "Querying session status and quotas..." | tee -a "$LOG_FILE"
    QUOTA_RESPONSE=$(curl -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" \
        -H "X-Requested-With: XMLHttpRequest" \
        "https://accor.conn4.com/wbs/api/v1/session-status/?authorization=session%3D${SESSION_ID}")
    echo "Quota/Status Response: $QUOTA_RESPONSE" | tee -a "$LOG_FILE"
}

# Run quota check once
check_quota

# 7. Connectivity check
echo "Step 8: Checking internet connectivity..." | tee -a "$LOG_FILE"
for i in {1..5}; do
    echo "Ping attempt $i..." | tee -a "$LOG_FILE"
    if ping -c 3 8.8.8.8 >/dev/null; then
        echo "Success: Internet access restored!" | tee -a "$LOG_FILE"
        rm -f "$COOKIE_JAR"
        exit 0
    fi
    sleep 3
done

echo "Error: Connectivity test failed after registration." | tee -a "$LOG_FILE"
rm -f "$COOKIE_JAR"
exit 1
#!/bin/sh
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/wifi_login.log"
COOKIE_JAR="$(mktemp)"
HTML_OUT="$(mktemp)"
trap 'rm -f "${COOKIE_JAR}" "${HTML_OUT}"' EXIT

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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

echo "Fetching initial portal page to trigger redirects and capture cookies..." | tee -a "$LOG_FILE"
# Follow redirects to land on the correct conn4 portal domain and record cookies
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{url_effective}" -o "$HTML_OUT" -m 20 "http://neverssl.com" | tr -d '\015')

echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extract the base domain dynamically from EFFECTIVE_URL
BASE_DOMAIN=$(echo "$EFFECTIVE_URL" | sed -n 's/\(https*:\/\/[^/]*\).*/\1/p')
if [ -z "$BASE_DOMAIN" ]; then
    echo "ERROR: Could not extract base domain from effective URL. Falling back to default." | tee -a "$LOG_FILE"
    BASE_DOMAIN="https://469.rdr.conn4.com"
fi
echo "Base domain: $BASE_DOMAIN" | tee -a "$LOG_FILE"

# Extract the wbsToken from the HTML
echo "Extracting wbsToken from HTML..." | tee -a "$LOG_FILE"
# The token is located in: conn4.hotspot.wbsToken = {"token":"..."
TOKEN=$(sed -n 's/.*conn4\.hotspot\.wbsToken = {"token":"\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')

if [ -z "$TOKEN" ]; then
    # Fallback pattern matching
    TOKEN=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')
fi

if [ -z "$TOKEN" ]; then
    echo "ERROR: Token extraction failed." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Extracted Token: $TOKEN" | tee -a "$LOG_FILE"

# Extract scene ID
echo "Extracting scene ID from schedule..." | tee -a "$LOG_FILE"
SCENE_ID=$(sed -n 's/.*"id":"\([^"]*\)","module":"html-page-scene-wbs-new".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')
if [ -z "$SCENE_ID" ]; then
    # Fallback to general id extraction in events
    SCENE_ID=$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')
fi
echo "Scene ID: $SCENE_ID" | tee -a "$LOG_FILE"

# Establish session via POST /wbs/api/v1/sessions
echo "Posting session initialization to backend API..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -X POST -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H "Content-Type: application/json" \
    -d "{"token":"$TOKEN"}" \
    -m 15 -w "\
HTTP_CODE:%{http_code}" "$BASE_DOMAIN/wbs/api/v1/sessions" | tr -d '\015')

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
echo "Session POST Response Code: $HTTP_CODE" | tee -a "$LOG_FILE"

# Next, we must call the scene API /wbs/api/v1/scenes/{id} or verify authorization
# Conn4 requires getting the scene configuration or requesting the grant URL.
# Let's request the scene configuration to trigger state change.
if [ ! -z "$SCENE_ID" ]; then
    echo "Fetching scene details for $SCENE_ID..." | tee -a "$LOG_FILE"
    SCENE_RESP=$(curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
        -m 15 -w "\
HTTP_CODE:%{http_code}" "$BASE_DOMAIN/wbs/api/v1/scenes/$SCENE_ID" | tr -d '\015')
    SCENE_CODE=$(echo "$SCENE_RESP" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
    echo "Scene GET Response Code: $SCENE_CODE" | tee -a "$LOG_FILE"
fi

# Since we are on a 'return' or 'roaming' login flow, we should attempt to hit the grant endpoint if provided,
# or submit the accept request. Many Conn4/Himalaya systems authorize directly upon session creation and scene load.
# Let's perform a direct trigger to authorize the MAC address on the portal gateway.
echo "Triggering portal activation endpoint..." | tee -a "$LOG_FILE"
ACTIVATE_RESP=$(curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -m 15 -w "\
HTTP_CODE:%{http_code}" "$BASE_DOMAIN/wbs/de/roaming/return/" | tr -d '\015')
ACTIVATE_CODE=$(echo "$ACTIVATE_RESP" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
echo "Activation Trigger Response Code: $ACTIVATE_CODE" | tee -a "$LOG_FILE"

# Let's perform the Internet connectivity check
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204" | tr -d '\015')
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1
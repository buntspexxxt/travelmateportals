#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/captive_portal.log"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'rm -f "${COOKIE_FILE}" "${HTML_FILE}"' EXIT

echo "Starting Conn4 multi-step automation..."

# Wait loop for network readiness
echo "Waiting for IP, Gateway, and DNS..."
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
BASE_URL="https://469.rdr.conn4.com"

echo "Step 1: Fetching initial portal and cookies..."
curl -k -v -m 15 -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" "$BASE_URL/"

echo "Step 2: Parsing WBS token and Scene ID from HTML..."
# We use sed to extract values from the JSON structure inside the JS script tag
SCENE_ID=$(sed -n 's/.*"id":"\([^"]*\)","module":"html-page-scene-wbs-new".*/\1/p' "$HTML_FILE" | head -n 1)
WBS_JSON=$(sed -n 's/.*conn4.hotspot.wbsToken = \({"token":.*"urls":{.*}}\);.*/\1/p' "$HTML_FILE" | head -n 1)

if [ -z "$SCENE_ID" ] || [ -z "$WBS_JSON" ]; then
    echo "Error: Failed to extract mandatory parameters. Exiting."
    exit 1
fi

TOKEN=$(echo "$WBS_JSON" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
echo "Extracted SCENE_ID: $SCENE_ID"

echo "Step 3: Submitting login/acceptance..."
# The portal requires a POST to the scene URL using the extracted token
curl -k -v -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$BASE_URL/scenes/$SCENE_ID/" \
    --data-urlencode "action=accept" \
    --data-urlencode "terms=1" \
    --data-urlencode "token=$TOKEN"

echo "Step 4: Requesting session transition..."
# Finalizing the session by hitting the return path found in WISP metadata
curl -k -v -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$BASE_URL/wbs/de/roaming/return/"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established."
exit 1
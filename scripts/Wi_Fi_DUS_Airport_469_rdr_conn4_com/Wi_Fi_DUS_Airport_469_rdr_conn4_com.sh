#!/bin/sh
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/captive_portal.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Conn4 multi-step automation..."

# 1. Smart wait loop
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

echo "Step 1: Detecting base URL..."
# We use the known base from previous analysis
BASE_URL="https://469.rdr.conn4.com"

echo "Step 2: Getting landing page to initialize cookies and session..."
curl -k -m 15 -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" "$BASE_URL/"

echo "Step 3: Extracting Scene ID and Token..."
# Extract SCENE_ID
SCENE_ID=$(sed -n 's/.*"id":"\([^""]*\)","module":"html-page-scene-wbs-new".*/\1/p' "$HTML_FILE" | head -n 1)
echo "Extracted SCENE_ID: $SCENE_ID"

# Extract WBS_TOKEN
WBS_TOKEN=$(sed -n 's/.*"token":"\([^""]*\)".*/\1/p' "$HTML_FILE" | head -n 1)
echo "Extracted WBS_TOKEN: $WBS_TOKEN"

if [ -z "$SCENE_ID" ]; then
    echo "Error: Failed to extract SCENE_ID. Exiting."
    exit 1
fi

echo "Step 4: Submitting Scene Accept (Accepting Terms)..."
RESPONSE=$(curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -X POST "${BASE_URL}/scenes/${SCENE_ID}/" \
    -d "action=accept&terms=1")

echo "Step 5: Verifying real Internet connectivity (polling for up to 40 seconds)..."
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
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds."
exit 1
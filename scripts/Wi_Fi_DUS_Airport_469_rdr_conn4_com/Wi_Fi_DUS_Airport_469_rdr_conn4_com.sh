#!/bin/sh
# SCRIPT_VERSION="1.0.0"
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/captive_portal.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Conn4 multi-step automation..."

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

echo "Step 1: Fetching initial state..."
curl -k -m 15 -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" "$BASE_URL/"

echo "Step 2: Extracting scene ID..."
SCENE_ID=$(sed -n 's/.*"id":"\([^"]*\)","module":"html-page-scene-wbs-new".*/\1/p' "$HTML_FILE" | head -n 1)
echo "Extracted SCENE_ID: $SCENE_ID"

if [ -z "$SCENE_ID" ]; then
    echo "Error: Failed to extract SCENE_ID. Exiting."
    exit 1
fi

echo "Step 3: Submitting scene POST to trigger login/terms..."
# Extracting token if present in HTML, though usually cookies handle the auth state for Conn4
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -X POST "${BASE_URL}/scenes/${SCENE_ID}/" \
    --data-urlencode "action=accept" --data-urlencode "terms=1"

echo "Step 4: Finalizing connection via roaming return..."
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "${BASE_URL}/wbs/de/roaming/return/"

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
#!/bin/bash
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/captive_portal.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Conn4 multi-step automation..."

# 1. Wait for network
echo "Waiting for IP, Gateway, and DNS..."
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!"
        sleep 2
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies_captive_portal.txt"

echo "Step 1: Accessing initial portal..."
curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /tmp/index.html "https://469.rdr.conn4.com/"

echo "Step 2: Extracting WBS Token..."
WBS_TOKEN=$(sed -n 's/.*conn4.hotspot.wbsToken = {"token":"\([^"]*\)",.*/\1/p' /tmp/index.html)
if [ -z "$WBS_TOKEN" ]; then echo "Failed to extract token"; exit 1; fi

echo "Step 3: Initializing session via POST..."
# We use the token to register the intent
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "https://469.rdr.conn4.com/wbs/de/roaming/return/" -d "token=$WBS_TOKEN"

echo "Step 4: Executing Scene Accept event..."
# The HTML/JS indicates the scene ID is 'agbRwik_7LwIN_lF'
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "https://469.rdr.conn4.com/scenes/agbRwik_7LwIN_lF/" -d "action=accept&terms=1"

echo "Step 5: Verifying final portal redirect state..."
# The provided HTML content is just a NeverSSL 'Connecting' placeholder. 
# This often implies the portal has finished the handshake and we should now reach the internet.

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
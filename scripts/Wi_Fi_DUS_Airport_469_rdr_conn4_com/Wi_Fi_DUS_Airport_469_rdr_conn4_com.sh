#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.1.0"
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

echo "Step 1: Detecting redirect URL..."
REDIRECT_URL=$(curl -k -m 15 -o /dev/null -w "%{redirect_url}" -A "$USER_AGENT" "http://neverssl.com")
echo "Redirect URL detected: $REDIRECT_URL"

if [ -z "$REDIRECT_URL" ]; then
    echo "No redirect URL returned. We might already be online or direct access is needed."
    REDIRECT_URL="https://469.rdr.conn4.com/"
fi

# Clean carriage returns safely using octal code
REDIRECT_URL=$(echo "$REDIRECT_URL" | tr -d '\015')

# Extract base domain dynamically
BASE_URL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
if [ -z "$BASE_URL" ] || [ "$BASE_URL" = "http:" ] || [ "$BASE_URL" = "https:" ]; then
    BASE_URL="https://469.rdr.conn4.com"
fi
echo "Using Base URL: $BASE_URL"

echo "Step 2: Initializing session by hitting redirect/ident URL..."
LANDING_HTML_FILE="/tmp/landing.html"
EFFECTIVE_URL=$(curl -k -m 15 -L -w "%{url_effective}" -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$LANDING_HTML_FILE" "$REDIRECT_URL")
echo "Effective Landing URL: $EFFECTIVE_URL"

echo "Step 3: Extracting WBS Token and Scene ID..."
WBS_TOKEN=$(sed -n 's/.*conn4.hotspot.wbsToken = {"token":"\([^"]*\)".*/\1/p' "$LANDING_HTML_FILE")
SCENE_ID=$(sed -n 's/.*"type":"scene","data":{"id":"\([^"]*\)".*/\1/p' "$LANDING_HTML_FILE")

if [ -z "$SCENE_ID" ]; then
    echo "Could not extract SCENE_ID from landing page. Using fallback 'agbRwik_7LwIN_lF'."
    SCENE_ID="agbRwik_7LwIN_lF"
else
    echo "Extracted SCENE_ID: $SCENE_ID"
fi

if [ -z "$WBS_TOKEN" ]; then
    echo "Could not extract WBS_TOKEN from landing page. Proceeding with scene accept..."
else
    echo "Extracted WBS_TOKEN: $WBS_TOKEN"
    echo "Step 3b: Submitting initial token to return endpoint..."
    curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
        -X POST "${BASE_URL}/wbs/de/roaming/return/" \
        -d "token=$WBS_TOKEN"
fi

echo "Step 4: Submitting Scene Accept (Accepting Terms)..."
SCENE_RESPONSE=$(curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -X POST "${BASE_URL}/scenes/${SCENE_ID}/" \
    -d "action=accept&terms=1")
echo "Scene Response: $SCENE_RESPONSE"

echo "Step 5: Processing Scene Response..."
# Extract potential new token, grant_url, or continue_url from the scene response
NEW_TOKEN=$(echo "$SCENE_RESPONSE" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
GRANT_URL=$(echo "$SCENE_RESPONSE" | sed -n 's/.*"grant_url":"\([^"]*\)".*/\1/p' | sed 's/\\//g')
CONTINUE_URL=$(echo "$SCENE_RESPONSE" | sed -n 's/.*"continue_url":"\([^"]*\)".*/\1/p' | sed 's/\\//g')

if [ -n "$NEW_TOKEN" ] && [ "$NEW_TOKEN" != "null" ]; then
    echo "Found new token: $NEW_TOKEN. Submitting to return endpoint..."
    curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
        -X POST "${BASE_URL}/wbs/de/roaming/return/" \
        -d "token=$NEW_TOKEN"
fi

if [ -n "$GRANT_URL" ] && [ "$GRANT_URL" != "null" ]; then
    echo "Found grant_url: $GRANT_URL. Executing grant request..."
    curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$GRANT_URL"
fi

if [ -n "$CONTINUE_URL" ] && [ "$CONTINUE_URL" != "null" ]; then
    echo "Found continue_url: $CONTINUE_URL. Executing continue request..."
    curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$CONTINUE_URL"
fi

# Fallback authorization attempt using the initial token in case it was authorized after the terms acceptance
if [ -n "$WBS_TOKEN" ]; then
    echo "Performing final authentication attempt with initial WBS Token..."
    curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
        -X POST "${BASE_URL}/wbs/de/roaming/return/" \
        -d "token=$WBS_TOKEN"
fi

# Cleanup
rm -f "$COOKIE_FILE" "$LANDING_HTML_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
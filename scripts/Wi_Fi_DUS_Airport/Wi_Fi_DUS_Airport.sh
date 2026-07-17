#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Clean up cookies and temp files on exit
LOG_FILE="/tmp/wifi_login.log"
COOKIE_JAR=$(mktemp)
HTML_OUT=$(mktemp)
trap 'rm -f "$COOKIE_JAR" "$HTML_OUT"' EXIT

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 11. Smart wait loop
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

echo "Initiating connection to neverssl.com to trigger captive portal redirect..."
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{url_effective}" -o "$HTML_OUT" "http://neverssl.com")

echo "Effective URL after redirect: $EFFECTIVE_URL"

# Extract Base URL dynamically
BASE_URL=$(echo "$EFFECTIVE_URL" | sed -n 's/\(https*:\/\/[^\/]*\).*/\1/p')
echo "Base URL of the captive portal: $BASE_URL"

if [ -z "$BASE_URL" ]; then
    echo "ERROR: Could not determine base URL from effective URL: $EFFECTIVE_URL"
    exit 1
fi

# Extract WBS Token dynamically using sed
echo "Extracting the wbsToken from the landing page..."
TOKEN=$(sed -n 's/.*conn4\.hotspot\.wbsToken *= *{"token":"\([^"]*\)".*/\1/p' "$HTML_OUT" | tr -d '\015')

if [ -z "$TOKEN" ]; then
    # Fallback parser if script tag formatting varies slightly
    TOKEN=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')
fi

echo "Extracted Token: $TOKEN"

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to extract WBS authentication token from HTML."
    exit 1
fi

# Attempt authentication via different standard CONN4 WBS API endpoints
echo "Trying API authentication via POST with JSON body..."
API_URL="${BASE_URL}/wbs/api/v1/sessions"
RESPONSE=$(curl -k -X POST -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{"token":"$TOKEN"}" \
    -m 15 \
    -w "
HTTP_CODE:%{http_code}" \
    "$API_URL")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1 | cut -d':' -f2 | tr -d '\015')
BODY=$(echo "$RESPONSE" | sed '$d')
echo "Response Body: $BODY"
echo "HTTP Code: $HTTP_CODE"

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "204" ]; then
    echo "JSON API returned $HTTP_CODE. Trying alternative: form-urlencoded POST..."
    RESPONSE=$(curl -k -X POST -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "token=$TOKEN" \
        -m 15 \
        -w "
HTTP_CODE:%{http_code}" \
        "$API_URL")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1 | cut -d':' -f2 | tr -d '\015')
    BODY=$(echo "$RESPONSE" | sed '$d')
    echo "Response Body: $BODY"
    echo "HTTP Code: $HTTP_CODE"
fi

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "204" ]; then
    echo "Trying alternative endpoint /wbs/api/sessions with JSON body..."
    API_URL="${BASE_URL}/wbs/api/sessions"
    RESPONSE=$(curl -k -X POST -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
        -H "Content-Type: application/json" \
        -d "{"token":"$TOKEN"}" \
        -m 15 \
        -w "
HTTP_CODE:%{http_code}" \
        "$API_URL")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1 | cut -d':' -f2 | tr -d '\015')
    BODY=$(echo "$RESPONSE" | sed '$d')
    echo "Response Body: $BODY"
    echo "HTTP Code: $HTTP_CODE"
fi

# 17. CRITICAL Connectivity verification
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

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds."
exit 1
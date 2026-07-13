#!/bin/sh

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"

# Smart wait loop for network ready
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

# Initialize cookie file
COOKIE_FILE=$(mktemp)

# Fetch landing page and follow redirects to get the final page and cookies
echo "Requesting neverssl.com to trigger captive portal redirect..."
LANDING_HTML=$(mktemp)
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o "$LANDING_HTML" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" --max-time 15 "http://neverssl.com")

echo "Effective URL: $EFFECTIVE_URL"

# Extract host
HOST=$(echo "$EFFECTIVE_URL" | cut -d'/' -f3)
echo "Portal Host: $HOST"

# Extract Token and full JSON
TOKEN=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LANDING_HTML" | head -n 1)
echo "Extracted Token: $TOKEN"

WBS_TOKEN_JSON=$(sed -n 's/.*conn4.hotspot.wbsToken = \({[^;]*}\);.*/\1/p' "$LANDING_HTML" | head -n 1)
echo "Extracted WBS Token JSON: $WBS_TOKEN_JSON"

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to extract WBS Token from HTML!"
    exit 1
fi

# Prepare POST payload
JSON_TEMP=$(mktemp)
if [ -n "$WBS_TOKEN_JSON" ]; then
    echo "$WBS_TOKEN_JSON" > "$JSON_TEMP"
else
    echo "{"token":"$TOKEN"}" > "$JSON_TEMP"
fi

echo "POST Payload:"
cat "$JSON_TEMP"

# Post authentication request
echo "Sending authentication to https://$HOST/wbs/api/auth..."
RESPONSE_HTML=$(mktemp)
HTTP_CODE=$(curl -k -v -X POST \
  -H "Content-Type: application/json" \
  -H "X-Requested-With: XMLHttpRequest" \
  -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -d "@$JSON_TEMP" \
  -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -w "%{http_code}" \
  -o "$RESPONSE_HTML" \
  --max-time 15 \
  "https://$HOST/wbs/api/auth")

echo "HTTP Code: $HTTP_CODE"
RESPONSE_CONTENT=$(cat "$RESPONSE_HTML")
echo "Response Content: $RESPONSE_CONTENT"

# Check for redirect_url or grant_url in JSON response
REDIRECT_URL_FROM_JSON=$(echo "$RESPONSE_CONTENT" | sed -n 's/.*"redirect_url":"\([^"]*\)".*/\1/p' | tr -d '\\')
GRANT_URL_FROM_JSON=$(echo "$RESPONSE_CONTENT" | sed -n 's/.*"grant_url":"\([^"]*\)".*/\1/p' | tr -d '\\')

if [ -n "$REDIRECT_URL_FROM_JSON" ] && [ "$REDIRECT_URL_FROM_JSON" != "null" ]; then
    echo "Following redirect URL from JSON: $REDIRECT_URL_FROM_JSON"
    curl -k -v -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
      -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
      --max-time 15 \
      "$REDIRECT_URL_FROM_JSON"
fi

if [ -n "$GRANT_URL_FROM_JSON" ] && [ "$GRANT_URL_FROM_JSON" != "null" ]; then
    echo "Following grant URL from JSON: $GRANT_URL_FROM_JSON"
    curl -k -v -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
      -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
      --max-time 15 \
      "$GRANT_URL_FROM_JSON"
fi

# Cleanup
rm -f "$LANDING_HTML" "$JSON_TEMP" "$RESPONSE_HTML" "$COOKIE_FILE"

# Real internet connectivity check
echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
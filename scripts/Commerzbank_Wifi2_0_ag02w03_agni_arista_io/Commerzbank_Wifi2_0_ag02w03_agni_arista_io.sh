#!/bin/sh
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/captive_portal_login.log"

echo "Starting Commerzbank Portal Login" | tee -a "$LOG_FILE"

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

COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching landing page to capture session parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -m 15 -k -L -A "$UA" -c "$COOKIE_FILE" -w "%\{url_effective\}" -o "$HTML_FILE" "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extract domain and query params dynamically using portable sed
BASE_URL=$(echo "$EFFECTIVE_URL" | sed -n 's|\(https\?://[^/]*\).*|\1|p')
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's|.*\?\(.*\)|\1|p')

# Step 1: Initial Login/Acceptance
LOGIN_API="${BASE_URL}/api/portal/login"
echo "Sending initial POST to $LOGIN_API" | tee -a "$LOG_FILE"

# We use --data-urlencode to safely handle the query string parameters
curl -m 15 -k -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -X POST "$LOGIN_API" \
    -H "Content-Type: application/json" \
    --data-urlencode "json={"accept_terms":true,"action":"login",$QUERY_STRING}" >> "$LOG_FILE" 2>&1

# Step 2: Some Arista/Agni portals require a session resume or state confirmation
AUTH_CHECK="${BASE_URL}/api/portal/session/resume"
echo "Performing session resume at $AUTH_CHECK" | tee -a "$LOG_FILE"
curl -m 15 -k -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X GET "$AUTH_CHECK" >> "$LOG_FILE" 2>&1

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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
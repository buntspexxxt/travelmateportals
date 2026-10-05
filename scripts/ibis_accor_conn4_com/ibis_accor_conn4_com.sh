#!/bin/sh
# SCRIPT_VERSION="2.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="/tmp/ibis_cookies.txt"
HTML_OUT="/tmp/portal_html.html"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
trap 'rm -f "${COOKIE_JAR:-}" "${HTML_OUT:-}"' EXIT

# 1. Wait for Network Readiness
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

# 2. Get the Initial Redirect
echo "Fetching initial URL to trigger portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -A "$USER_AGENT" -o /dev/null -w "%{redirect_url}" -m 15 "http://neverssl.com")
echo "Initial Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

if [ -z "$REDIRECT_URL" ]; then
    echo "No redirect detected. Checking if already connected..." | tee -a "$LOG_FILE"
else
    # Follow redirect to get the page and cookies
    echo "Following redirect and storing cookies..." | tee -a "$LOG_FILE"
    EFFECTIVE_URL=$(curl -k -A "$USER_AGENT" -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "$REDIRECT_URL")
    echo "Effective landing URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"
fi

# Extract base host from EFFECTIVE_URL
BASE_HOST=$(echo "$EFFECTIVE_URL" | sed -n 's/\(https*:\/\/[^\/]*\).*/\1/p')
if [ -z "$BASE_HOST" ]; then
    BASE_HOST="https://accor.conn4.com"
fi
echo "Using Base Host: $BASE_HOST" | tee -a "$LOG_FILE"

# Extract scenePlayerUri from HTML_OUT
# It looks like: "scenePlayerUri":"\/sscp\/iGKzCQzLrzwyM4q1\/"
SCENE_PLAYER_URI=$(grep -o '"scenePlayerUri":"[^"]*"' "$HTML_OUT" | sed -n 's/.*"scenePlayerUri":"\([^"]*\)".*/\1/p' | sed 's/\\//g')

if [ -z "$SCENE_PLAYER_URI" ]; then
    echo "ERROR: Could not find scenePlayerUri in landing page! Trying fallback..." | tee -a "$LOG_FILE"
    SCENE_PLAYER_URI="/sscp/iGKzCQzLrzwyM4q1/"
fi
echo "Extracted scenePlayerUri: $SCENE_PLAYER_URI" | tee -a "$LOG_FILE"

# Let's hit the scenePlayerUri to retrieve state metadata / options
# This often has an API endpoint or redirects to options page.
SCENE_URL="${BASE_HOST}${SCENE_PLAYER_URI}"
echo "Requesting scene endpoint: $SCENE_URL" | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o "$HTML_OUT" -m 15 "$SCENE_URL"

# At this point, Conn4 portals typically expect a POST request to login or activate
# The endpoint is often /sscp/<session-id>/api/login or /sscp/<session-id>/api/wbs/connect
# Let's extract the session ID from the SCENE_PLAYER_URI
SESSION_PATH_ID=$(echo "$SCENE_PLAYER_URI" | sed -n 's/\/sscp\/\([^\/]*\)\/.*/\1/p')
echo "Extracted Session Path ID: $SESSION_PATH_ID" | tee -a "$LOG_FILE"

# Submit a standard free connect request to the conn4 backend
# Typically, Conn4 uses JSON POST requests for API-based logins. Let's try connecting using the common JSON format or form-data for WBS free login.
CONNECT_URL="${BASE_HOST}/sscp/${SESSION_PATH_ID}/api/wbs/connect"
echo "Posting to Conn4 login endpoint: $CONNECT_URL" | tee -a "$LOG_FILE"

# Payloads for Conn4 generally accept standard free terms parameters:
# We pass empty strings for credentials or just accept terms.
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"termsAndConditionsAccepted":true,"newsletter":false,"privacyPolicyAccepted":true}' \
  -w "
HTTP_CODE: %{http_code}" \
  "$CONNECT_URL")

echo "Response from API connect: $RESPONSE" | tee -a "$LOG_FILE"

# Polling verification
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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
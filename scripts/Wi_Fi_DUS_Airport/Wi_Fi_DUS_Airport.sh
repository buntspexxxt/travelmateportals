#!/bin/sh
# SCRIPT_VERSION="1.0.0"
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

# Previous step: Fetch initial portal page and extract token
echo "Fetching initial portal page to capture token..." | tee -a "$LOG_FILE"
# The previous script used http://neverssl.com, which might not be the ideal initial redirect. 
# We'll reuse the logic to ensure we land on the correct portal page.
# We will use a curl command that follows redirects to get the final HTML.
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{url_effective}" -o "$HTML_OUT" "http://neverssl.com" | tr -d '\015')

# Check if the curl command was successful
HTTP_STATUS=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o /dev/null -w "%{http_code}" "http://neverssl.com" | tr -d '\015')

if [ "$HTTP_STATUS" -ne 200 ] && [ "$HTTP_STATUS" -ne 302 ]; then
    echo "ERROR: Failed to fetch initial portal page. HTTP Status: $HTTP_STATUS" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Initial portal page fetched. Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Extracting WBS Token from HTML..." | tee -a "$LOG_FILE"
TOKEN=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')
if [ -z "$TOKEN" ]; then
    echo "ERROR: Token extraction failed." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Attempting to start scene session with token: $TOKEN" | tee -a "$LOG_FILE"
# Based on the HTML, the portal expects to load a scene via an internal API
RESPONSE=$(curl -k -X POST -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H "Content-Type: application/json" \
    -d "{"token":"$TOKEN"}" \
    -m 15 -w "
HTTP_CODE:%{http_code}" "https://469.rdr.conn4.com/wbs/api/v1/sessions" | tr -d '\015')

# Extract HTTP code from response
HTTP_CODE=$(echo "$RESPONSE" | grep -oP 'HTTP_CODE:\K.*')
RESPONSE_BODY=$(echo "$RESPONSE" | grep -oP '^(.*)HTTP_CODE:' | sed 's/HTTP_CODE:$//' | tr -d '\015')

echo "Response body: $RESPONSE_BODY" | tee -a "$LOG_FILE"
echo "HTTP Status Code: $HTTP_CODE" | tee -a "$LOG_FILE"

if [ "$HTTP_CODE" -ne 200 ]; then
    echo "ERROR: Scene session start failed. HTTP Status: $HTTP_CODE" | tee -a "$LOG_FILE"
    exit 1
fi

# New step: Handle the second page, which appears to be a confirmation/loading page.
# The previous script executed the initial POST request. The current HTML indicates
# that the system is now loading a scene. We need to wait for this scene to load and
# then verify internet connectivity.

# The provided HTML is the result *after* the initial login attempt. It contains JavaScript
# that loads a scene. We've already performed the POST request to initiate the scene loading.
# The crucial part now is to wait for this loading process to complete and then check for internet.
# The existing script already has a connectivity check at the end, which we will keep.

# We need to ensure that the previous POST request was successful and the subsequent
# JavaScript execution on the client side (which we can't directly control in a curl script)
# eventually leads to an authorized state.

# Given that the previous script likely landed on a page that triggered the provided HTML, 
# and the goal is to append logic for *this* page, our next action is to trust that
# the previous POST call was correct and that the system will eventually grant access.
# The provided HTML itself doesn't contain explicit forms or buttons to submit for this step,
# it seems to be a state where the portal is waiting for backend authorization after the initial POST.

# Therefore, the logic should proceed directly to the internet connectivity check.


echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{{http_code}}" -m 8 "http://connectivitycheck.gstatic.com/generate_204" | tr -d '\015')
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

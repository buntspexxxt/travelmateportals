#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Ensure clean temp files and cookie jar
COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Wait for network interface to be fully ready
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

# Step 1: Detect captive portal by hitting neverssl.com
echo "Detecting captive portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -o /dev/null -w "%{redirect_url}" -m 15 -A "$USER_AGENT" "http://neverssl.com")
if [ -z "$REDIRECT_URL" ]; then
    echo "No redirect detected. Checking if we already have internet..." | tee -a "$LOG_FILE"
else
    echo "Redirected to: $REDIRECT_URL" | tee -a "$LOG_FILE"
fi

# Step 2: Request the redirect URL to fetch cookies and potential WISPAccessGatewayParam
echo "Fetching redirect page to obtain session cookies..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_OUT" -m 15 -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$REDIRECT_URL")
echo "Effective URL after redirect: $EFFECTIVE_URL" | tee -a "$LOG_FILE"
rm -f "$HTML_OUT"

# Step 3: Trigger the roaming return endpoint to get the ident redirect
echo "Accessing the roaming return URL to trigger ident signature generation..." | tee -a "$LOG_FILE"
RETURN_OUT=$(mktemp)
# Follow redirects carefully to catch the 'ident' location
IDENT_URL=$(curl -k -s -o /dev/null -w "%{redirect_url}" -m 15 -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "https://wbs-rewe.conn4.com/de/roaming/return/")
IDENT_URL=$(echo "$IDENT_URL" | tr -d "\015")
echo "Ident URL extracted: $IDENT_URL" | tee -a "$LOG_FILE"
rm -f "$RETURN_OUT"

if [ -z "$IDENT_URL" ]; then
    echo "Failed to obtain Ident URL. Trying to access root of wbs-rewe directly to see if it redirects..." | tee -a "$LOG_FILE"
    IDENT_URL=$(curl -k -s -o /dev/null -w "%{redirect_url}" -m 15 -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "https://wbs-rewe.conn4.com/")
    IDENT_URL=$(echo "$IDENT_URL" | tr -d "\015")
    echo "Direct root Ident URL: $IDENT_URL" | tee -a "$LOG_FILE"
fi

# Step 4: Load the ident page which generates the session and includes the JS with wbsToken
echo "Loading Ident page to fetch the wbsToken..." | tee -a "$LOG_FILE"
IDENT_HTML=$(mktemp)
curl -k -m 15 -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" -o "$IDENT_HTML" "$IDENT_URL"

# Extract the token string using POSIX sed from: conn4.hotspot.wbsToken = {"token":"..."
TOKEN=$(sed -n 's/.*conn4\.hotspot\.wbsToken = {"token":"\([^"]*\)".*/\1/p' "$IDENT_HTML")
echo "Extracted Token: $TOKEN" | tee -a "$LOG_FILE"
rm -f "$IDENT_HTML"

if [ -z "$TOKEN" ]; then
    echo "ERROR: Could not extract wbsToken from page. Cannot proceed with activation." | tee -a "$LOG_FILE"
    exit 1
fi

# Step 5: Perform the login/activation POST
# m3connect/conn4 portals require accepting the terms by POSTing the token back to the roaming return or activation endpoint.
# Usually, we POST to the roaming return endpoint with the token as payload.
echo "Submitting activation token to register connection..." | tee -a "$LOG_FILE"

# Formulate activation payload (often sent as token=TOKEN or JSON depending on context, we will send both formats if needed or standard POST)
ACTIVATE_RESPONSE=$(mktemp)
curl -k -m 15 -X POST -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
     --data-urlencode "token=$TOKEN" \
     --data-urlencode "accept_terms=1" \
     --data-urlencode "connect=" \
     -o "$ACTIVATE_RESPONSE" \
     "https://wbs-rewe.conn4.com/de/roaming/return/"

HTTP_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" -m 15 -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "https://wbs-rewe.conn4.com/de/roaming/return/")
echo "Activation POST HTTP Status: $HTTP_STATUS" | tee -a "$LOG_FILE"
rm -f "$ACTIVATE_RESPONSE"

# Step 6: Verify real Internet connectivity (polling for up to 40 seconds)
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

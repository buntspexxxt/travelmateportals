#!/bin/sh
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting portal login process..." | tee -a "$LOG_FILE"

# 1. Network Wait
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

# 2. Setup environment
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# 3. Extract Token and WISPr Login URL
TOKEN=$(grep -o 'wbsToken = {[^}]*}' "$HTML_OUT" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
if [ -z "$TOKEN" ]; then
    TOKEN=$(sed -n 's/.*"token":"\([a-zA-Z0-9+/=]\{50,\}\)".*/\1/p' "$HTML_OUT" | head -n 1)
fi

if [ -z "$TOKEN" ]; then
    echo "Error: Could not extract wbsToken from HTML. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Extracted Token: $TOKEN" | tee -a "$LOG_FILE"

WISPR_LOGIN_URL=$(sed -n 's/.*<LoginURL>\([^<]*\)<\/LoginURL>.*/\1/p' "$HTML_OUT" | head -n 1 | sed "s/\r//g")
if [ -z "$WISPR_LOGIN_URL" ]; then
    echo "Warning: WISPr LoginURL not found in HTML, using default fallback." | tee -a "$LOG_FILE"
    WISPR_LOGIN_URL="https://wbs-rewe.conn4.com/de/roaming/return/"
fi
echo "WISPr Gateway Login URL: $WISPR_LOGIN_URL" | tee -a "$LOG_FILE"

API_HOST=$(echo "$EFFECTIVE_URL" | awk -F/ '{print $3}')
GRANT_URL="https://$API_HOST/grant"

# Strategy 1: POST Token as JSON to /grant (WBS API often expects application/json)
echo "[Strategy 1] Sending JSON payload to $GRANT_URL..." | tee -a "$LOG_FILE"
JSON_PAYLOAD='{"token":"'$TOKEN'"}'
RESPONSE_CODE=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -d "$JSON_PAYLOAD" -m 15 "$GRANT_URL")
echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

# Strategy 2: POST Full token object as JSON to /grant
if [ "$RESPONSE_CODE" != "200" ] && [ "$RESPONSE_CODE" != "302" ]; then
    echo "[Strategy 2] Sending full JSON payload to $GRANT_URL..." | tee -a "$LOG_FILE"
    JSON_PAYLOAD2='{"token":"'$TOKEN'","urls":{"grant_url":null,"continue_url":null}}'
    RESPONSE_CODE=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -d "$JSON_PAYLOAD2" -m 15 "$GRANT_URL")
    echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"
fi

# Strategy 3: GET with Token directly to WISPr Login URL
if [ "$RESPONSE_CODE" != "200" ] && [ "$RESPONSE_CODE" != "302" ]; then
    echo "[Strategy 3] Sending GET request to WISPr Login URL..." | tee -a "$LOG_FILE"
    RESPONSE_CODE=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" -G --data-urlencode "token=$TOKEN" -m 15 "$WISPR_LOGIN_URL")
    echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"
fi

# Strategy 4: POST Form-encoded Token to WISPr Login URL
if [ "$RESPONSE_CODE" != "200" ] && [ "$RESPONSE_CODE" != "302" ]; then
    echo "[Strategy 4] Sending form POST to WISPr Login URL..." | tee -a "$LOG_FILE"
    RESPONSE_CODE=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" --data-urlencode "token=$TOKEN" -m 15 "$WISPR_LOGIN_URL")
    echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"
fi

# Strategy 5: POST Form-encoded Token to /grant (Fallback)
if [ "$RESPONSE_CODE" != "200" ] && [ "$RESPONSE_CODE" != "302" ]; then
    echo "[Strategy 5] Sending form POST to $GRANT_URL..." | tee -a "$LOG_FILE"
    RESPONSE_CODE=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" --data-urlencode "token=$TOKEN" -m 15 "$GRANT_URL")
    echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"
fi

# 4. Connectivity Check
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
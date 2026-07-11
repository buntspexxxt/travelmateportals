#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
echo 'Starting WiFi4EU portal login process...' | tee -a "$LOG_FILE"

# Smart wait loop (Rule 11)
echo 'Waiting for IP, Gateway, and DNS...' | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo 'Network and DNS are ready!' | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

COOKIE_FILE=$(mktemp)
USER_AGENT='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

echo 'Step 1: Detecting initial portal redirect URL...' | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -o /dev/null -w '%{redirect_url}' 'http://neverssl.com')
echo "Portal redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

if [ -z "$REDIRECT_URL" ]; then
    echo 'No redirect detected. Checking if we already have Internet...' | tee -a "$LOG_FILE"
else
    echo 'Step 2: Accessing portal landing page to establish cookies...' | tee -a "$LOG_FILE"
    HTML=$(curl -m 15 -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$REDIRECT_URL")
    echo "Landing page fetched. Length: ${#HTML} characters" | tee -a "$LOG_FILE"

    echo 'Step 3: Dynamically extracting Get Online URL from page HTML...' | tee -a "$LOG_FILE"
    # Safe portable parsing avoiding complex quote escaping
    GET_ONLINE_URL=$(echo "$HTML" | grep -o "href=[^ >]*" | head -n 1 | sed 's/href=//' | sed "s/'//g" | sed 's/"//g')
    echo "Extracted raw Get Online URL: $GET_ONLINE_URL" | tee -a "$LOG_FILE"

    if [ -n "$GET_ONLINE_URL" ]; then
        # Form absolute URL if relative
        case "$GET_ONLINE_URL" in
            http*)
                ;;
            *)
                BASE_URL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
                GET_ONLINE_URL="${BASE_URL}${GET_ONLINE_URL}"
                echo "Formed absolute Get Online URL: $GET_ONLINE_URL" | tee -a "$LOG_FILE"
                ;;
        esac
    else
        echo 'Warning: Could not extract Get Online link. Using fallback static path.' | tee -a "$LOG_FILE"
        BASE_URL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
        GET_ONLINE_URL="${BASE_URL}/service-platform/url/20347"
    fi

    echo 'Step 4: Requesting the action URL and following redirects...' | tee -a "$LOG_FILE"
    # Follow redirects so curl triggers the underlying /getonline authorization route
    GET_ONLINE_RESPONSE=$(curl -m 15 -k -L -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$GET_ONLINE_URL")
    echo "Get Online response received." | tee -a "$LOG_FILE"

    echo 'Step 5: Simulating drift_time_204 check as seen in splash JavaScript...' | tee -a "$LOG_FILE"
    BASE_URL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
    DRIFT_URL="${BASE_URL}/service-platform/drift_time_204"
    DRIFT_RESPONSE=$(curl -m 15 -k -L -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$DRIFT_URL")
    echo "Drift endpoint response captured." | tee -a "$LOG_FILE"
fi

# Critical verification check (Rule 17)
echo 'Verifying real Internet connectivity...' | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo 'SUCCESS: Internet connection verified!' | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
#!/bin/sh
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_FILE"' EXIT

touch "$LOG_FILE"

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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Step 1: Fetching initial redirect from neverssl.com..." | tee -a "$LOG_FILE"
REDIRECT_DO=$(curl -k -A "$USER_AGENT" -o /dev/null -w "%{redirect_url}" -m 15 "http://neverssl.com")
REDIRECT_DO=$(echo "$REDIRECT_DO" | tr -d '\015')

echo "Initial Redirect DO URL: $REDIRECT_DO" | tee -a "$LOG_FILE"

if [ -z "$REDIRECT_DO" ]; then
    echo "ERROR: Failed to retrieve redirect URL from neverssl.com. We might already be online." | tee -a "$LOG_FILE"
else
    echo "Step 2: Fetching redirect page content to locate login token/URL..." | tee -a "$LOG_FILE"
    curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -m 15 -o "$HTML_FILE" "$REDIRECT_DO"

    echo "Attempting to extract <loginurl> from redirect.do..." | tee -a "$LOG_FILE"
    LOGIN_URL=$(sed -n 's/.*<loginurl>\([^<]*\)<\/loginurl>.*/\1/p' "$HTML_FILE" | sed 's/&amp;/\&/g' | tr -d '\015')

    if [ -z "$LOGIN_URL" ]; then
        echo "Login URL not found in direct redirect response. Fetching landing page..." | tee -a "$LOG_FILE"
        LANDING_URL=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{redirect_url}" -m 15 "$REDIRECT_DO")
        LANDING_URL=$(echo "$LANDING_URL" | tr -d '\015')
        echo "Landing URL: $LANDING_URL" | tee -a "$LOG_FILE"

        if [ -n "$LANDING_URL" ]; then
            curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o "$HTML_FILE" -m 15 "$LANDING_URL"
            LOGIN_URL=$(sed -n 's/.*<loginurl>\([^<]*\)<\/loginurl>.*/\1/p' "$HTML_FILE" | sed 's/&amp;/\&/g' | tr -d '\015')
        fi
    fi

    echo "Extracted Login URL: $LOGIN_URL" | tee -a "$LOG_FILE"

    if [ -z "$LOGIN_URL" ]; then
        echo "Warning: LOGIN_URL still empty. Constructing fallback login URL..." | tee -a "$LOG_FILE"
        QUERY_STRING=$(echo "$REDIRECT_DO" | grep -o '?.*')
        if [ -z "$QUERY_STRING" ]; then
            QUERY_STRING=$(echo "$LANDING_URL" | grep -o '?.*')
        fi
        LOGIN_URL="https://hotspot.t-mobile.net/wlan/rest/freeLogin${QUERY_STRING}"
        echo "Constructed Fallback Login URL: $LOGIN_URL" | tee -a "$LOG_FILE"
    fi

    echo "Step 3: Submitting login credentials to Telekom Hotspot gateway..." | tee -a "$LOG_FILE"
    RESPONSE=$(curl -k -v -A "$USER_AGENT" \
        -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
        --referer "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
        --data-urlencode "UserName=" \
        --data-urlencode "Password=" \
        --data-urlencode "FNAME=0" \
        --data-urlencode "button=Login" \
        --data-urlencode "OriginatingServer=http://neverssl.com/" \
        -m 20 \
        "$LOGIN_URL")

    echo "Login Response Body:" | tee -a "$LOG_FILE"
    echo "$RESPONSE" >> "$LOG_FILE"

    LOGOFF_URL=$(echo "$RESPONSE" | sed -n 's/.*<logoffurl>\([^<]*\)<\/logoffurl>.*/\1/p' | sed 's/&amp;/\&/g' | tr -d '\015')
    if [ -n "$LOGOFF_URL" ]; then
        echo "SUCCESS: Logoff URL acquired: $LOGOFF_URL" | tee -a "$LOG_FILE"
    else
        echo "Warning: Logoff URL was not returned. Checking internet status anyway." | tee -a "$LOG_FILE"
    fi
fi

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
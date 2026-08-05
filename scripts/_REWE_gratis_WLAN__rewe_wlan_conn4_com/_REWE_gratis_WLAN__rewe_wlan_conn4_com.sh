#!/bin/sh
# SCRIPT_VERSION="1.2.0"

LOG_FILE="/tmp/wifi_login.log"
COOKIE_JAR="/tmp/cookies.txt"
HTML_OUT="/tmp/rewe_page.html"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

trap 'rm -f "$COOKIE_JAR" "$HTML_OUT"' EXIT

echo "Waiting for DHCP & DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Gateway and DNS found!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Detecting initial portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -s -o /dev/null -w "%{redirect_url}" -m 15 -A "$USER_AGENT" "http://neverssl.com" | tr -d '\015')

if [ -z "$REDIRECT_URL" ]; then
    REDIRECT_URL="https://wbs-rewe.conn4.com/de/roaming/return/"
fi

echo "Fetching initial portal page ($REDIRECT_URL)..." | tee -a "$LOG_FILE"
curl -k -m 15 -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" -o "$HTML_OUT" "$REDIRECT_URL"

# Extract meta refresh ident URL if present
REFRESH_URL=$(grep -ioE 'url=[^"'\'' >]+' "$HTML_OUT" | head -n 1 | sed 's/url=//i' | sed 's/&amp;/&/g' | tr -d '"'\''\015')

if [ -n "$REFRESH_URL" ]; then
    echo "Meta refresh ident URL found: $REFRESH_URL" | tee -a "$LOG_FILE"
    curl -k -m 15 -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" -o "$HTML_OUT" "$REFRESH_URL"
fi

# Extract wbsToken
TOKEN=$(sed -n 's/.*conn4\.hotspot\.wbsToken = {"token":"\([^"]*\)".*/\1/p' "$HTML_OUT")

if [ -n "$TOKEN" ]; then
    echo "Extracted wbsToken: $TOKEN" | tee -a "$LOG_FILE"
    echo "Submitting activation token..." | tee -a "$LOG_FILE"
    curl -k -m 15 -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
        --data-urlencode "token=$TOKEN" \
        --data-urlencode "accept_terms=1" \
        "https://wbs-rewe.conn4.com/de/roaming/return/" >/dev/null 2>&1
else
    echo "No wbsToken found, trying direct return URL hit..." | tee -a "$LOG_FILE"
    curl -k -m 15 -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "https://wbs-rewe.conn4.com/de/roaming/return/" >/dev/null 2>&1
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

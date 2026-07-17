#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_FILE"' EXIT

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Capturing redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_FILE" -A "$USER_AGENT" "http://neverssl.com")

echo "Extracting Login URL..." | tee -a "$LOG_FILE"
LOGIN_URL=$(sed -n 's/.*<loginurl>\([^<]*\)<\/loginurl>.*/\1/p' "$HTML_FILE" | sed 's/&amp;/\&/g' | tr -d '\115')

if [ -z "$LOGIN_URL" ]; then
    echo "ERROR: No login URL found" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting initial free login..." | tee -a "$LOG_FILE"
curl -v -k -m 15 -b "$COOKIE_FILE" -c "$COOKIE_FILE" -A "$USER_AGENT" \
    --data-urlencode "UserName=" \
    --data-urlencode "Password=" \
    --data-urlencode "FNAME=0" \
    --data-urlencode "button=Login" \
    --data-urlencode "OriginatingServer=http://neverssl.com" "$LOGIN_URL" > /dev/null 2>&1

echo "Accessing REST session endpoint..." | tee -a "$LOG_FILE"
curl -v -k -m 15 -b "$COOKIE_FILE" -c "$COOKIE_FILE" -A "$USER_AGENT" "https://hotspot.t-mobile.net/wlan/rest/login/session" > /dev/null 2>&1

echo "Verifying internet..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Connected!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Checking..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done
exit 1
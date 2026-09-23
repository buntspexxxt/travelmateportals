#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="/tmp/ibis_cookies.txt"
HTML_OUT="/tmp/portal_html.html"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
trap 'rm -f "${COOKIE_JAR:-}" "${HTML_OUT:-}"' EXIT

echo "Waiting for network readiness..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready!" | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -A "$USER_AGENT" -L -c "$COOKIE_JAR" -w "%\{url_effective\}" -o "$HTML_OUT" -m 15 "http://neverssl.com")
echo "Current URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Extracting form data..." | tee -a "$LOG_FILE"
# Extract form action and fields dynamically from the HTML
FORM_ACTION=$(sed -n 's/.*<form.*action="\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | sed 's/&amp;/\&/g')

# Helper to extract input values
extract_val() {
    sed -n "s/.*name="$1" value="\([^"]*\)".*/\1/p" "$HTML_OUT" | head -n 1 | sed 's/&#x3D;/=/g'
}

CBQPC=$(extract_val "cbQpC")
NASID=$(extract_val "nasid")
MAC=$(extract_val "mac")
CHALLENGE=$(extract_val "challenge")
UAMIP=$(extract_val "uamip")
UAMPORT=$(extract_val "uamport")
CALLED=$(extract_val "called")
USERURL=$(extract_val "userurl")
SESSIONID=$(extract_val "sessionid")
USERNAME=$(extract_val "FX_username")
PASSWORD="easy"
TEMPLATE=$(extract_val "FX_loginTemplate")
LOGIN_TYPE="Easy Login"
DEVICE_ID=$(extract_val "FX_hotspotDeviceId")

echo "Submitting login form to $FORM_ACTION..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 -X POST \
--data-urlencode "cbQpC=$CBQPC" \
--data-urlencode "nasid=$NASID" \
--data-urlencode "mac=$MAC" \
--data-urlencode "challenge=$CHALLENGE" \
--data-urlencode "uamip=$UAMIP" \
--data-urlencode "uamport=$UAMPORT" \
--data-urlencode "called=$CALLED" \
--data-urlencode "userurl=$USERURL" \
--data-urlencode "sessionid=$SESSIONID" \
--data-urlencode "FX_username=$USERNAME" \
--data-urlencode "FX_password=$PASSWORD" \
--data-urlencode "FX_loginTemplate=$TEMPLATE" \
--data-urlencode "FX_loginType=$LOGIN_TYPE" \
--data-urlencode "FX_hotspotDeviceId=$DEVICE_ID" \
"$FORM_ACTION")

echo "Login response received. Verifying connectivity..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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
#!/bin/sh
# SCRIPT_VERSION="1.1.0"

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT

echo "Starting Login Script..." | tee -a "$LOG_FILE"

# Wait for network
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
USERNAME=""
PASSWORD=""

echo "Step 1: Accessing captive portal..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_OUT" -m 15 -A "$USER_AGENT" -c "$COOKIE_FILE" "http://neverssl.com")
echo "Effective URL reached: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Step 2: Parsing login page parameters..." | tee -a "$LOG_FILE"
HEXMD5_LINE=$(grep "hexMD5" "$HTML_OUT" | head -n 1)
if [ -z "$HEXMD5_LINE" ]; then
    echo "Error: Could not find hexMD5 line in HTML. The portal might have changed or already authenticated." | tee -a "$LOG_FILE"
    exit 1
fi

# Normalize line to use double quotes instead of single quotes for reliable parsing
HEXMD5_LINE_NORM=$(echo "$HEXMD5_LINE" | tr "'" '"')

CHAP_ID_OCTAL=$(echo "$HEXMD5_LINE_NORM" | sed -n 's/.*hexMD5("\([^"]*\)".*/\1/p' | tr -d '\015')
CHAP_CHALLENGE_OCTAL=$(echo "$HEXMD5_LINE_NORM" | sed -n 's/.*password.value + "\([^"]*\)".*/\1/p' | tr -d '\015')

echo "Extracted CHAP ID Octal: $CHAP_ID_OCTAL" | tee -a "$LOG_FILE"
echo "Extracted CHAP Challenge Octal: $CHAP_CHALLENGE_OCTAL" | tee -a "$LOG_FILE"

if [ -z "$CHAP_ID_OCTAL" ] || [ -z "$CHAP_CHALLENGE_OCTAL" ]; then
    echo "Error: Failed to parse CHAP ID or Challenge." | tee -a "$LOG_FILE"
    exit 1
fi

# Extract target URL / form action
FORM_ACTION=$(grep -i 'name="login"' "$HTML_OUT" | sed -n 's/.*action="\([^"]*\)".*/\1/p' | tr -d '\015')
echo "Form Action: $FORM_ACTION" | tee -a "$LOG_FILE"

BASE_HOST=$(echo "$EFFECTIVE_URL" | awk -F/ '{print $1"//"$3}')
case "$FORM_ACTION" in
    http://*|https://*)
        LOGIN_URL="$FORM_ACTION"
        ;;
    /*)
        LOGIN_URL="${BASE_HOST}${FORM_ACTION}"
        ;;
    *)
        LOGIN_URL="${BASE_HOST}/${FORM_ACTION}"
        ;;
esac
echo "Resolved Login URL: $LOGIN_URL" | tee -a "$LOG_FILE"

# Extract hidden inputs
DST_VAL=$(sed -n 's/.*name="dst" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')
POPUP_VAL=$(sed -n 's/.*name="popup" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')

[ -z "$DST_VAL" ] && DST_VAL="http://detectportal.firefox.com/success.txt"
[ -z "$POPUP_VAL" ] && POPUP_VAL="true"

# Compute MD5 CHAP Password using printf to safely parse dynamic octal string sequences
echo "Step 3: Computing CHAP MD5 hash..." | tee -a "$LOG_FILE"
CHAP_PASSWORD_HASH=$(printf "${CHAP_ID_OCTAL}%s${CHAP_CHALLENGE_OCTAL}" "${PASSWORD}" | md5sum | awk '{print $1}')
echo "Computed CHAP Password Hash: $CHAP_PASSWORD_HASH" | tee -a "$LOG_FILE"

echo "Step 4: Submitting login credentials..." | tee -a "$LOG_FILE"
curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o "$HTML_OUT" -m 15 \
    -w "HTTP Response: %{http_code}
" \
    --data-urlencode "username=${USERNAME}" \
    --data-urlencode "password=${CHAP_PASSWORD_HASH}" \
    --data-urlencode "dst=${DST_VAL}" \
    --data-urlencode "popup=${POPUP_VAL}" \
    "$LOGIN_URL" | tee -a "$LOG_FILE"

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
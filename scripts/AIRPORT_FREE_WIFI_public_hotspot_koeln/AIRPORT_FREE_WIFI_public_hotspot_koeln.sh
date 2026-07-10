#!/bin/bash
# SCRIPT_VERSION="1.1.0"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
echo "Starting portal login sequence..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Checking redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -o /dev/null -w "%{redirect_url}" "http://neverssl.com")
REDIRECT_URL=$(echo "$REDIRECT_URL" | tr -d '\015')

if [ -z "$REDIRECT_URL" ]; then
    echo "No redirect URL detected, using default landing page..." | tee -a "$LOG_FILE"
    REDIRECT_URL="https://public.hotspot.koeln/cp/guqs6n9d"
else
    echo "Detected redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"
fi

HOST=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
if [ -z "$HOST" ]; then
    HOST="https://public.hotspot.koeln"
fi
echo "Extracted Host: $HOST" | tee -a "$LOG_FILE"

echo "Fetching landing page: $REDIRECT_URL" | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_FILE" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" "$REDIRECT_URL")
EFFECTIVE_URL=$(echo "$EFFECTIVE_URL" | tr -d '\015')
echo "Effective URL after redirect: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

FORM_ACTION=$(grep -o 'action="[^"]*"' "$HTML_FILE" | head -n1 | cut -d'"' -f2)
if [ -z "$FORM_ACTION" ]; then
    FORM_ACTION="/login"
fi

if echo "$FORM_ACTION" | grep -q "^/"; then
    LOGIN_URL="${HOST}${FORM_ACTION}"
else
    LOGIN_URL="$FORM_ACTION"
fi
echo "Determined Login URL: $LOGIN_URL" | tee -a "$LOG_FILE"

echo "Submitting login form with checkbox agreement..." | tee -a "$LOG_FILE"
REDIRECT_SUCCESS=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -d "login=oneclick" \
  -d "customControlValidation1=on" \
  -w "%{redirect_url}" \
  -o /dev/null \
  "$LOGIN_URL")
REDIRECT_SUCCESS=$(echo "$REDIRECT_SUCCESS" | tr -d '\015')

echo "Login submission redirect URL: $REDIRECT_SUCCESS" | tee -a "$LOG_FILE"

if [ -n "$REDIRECT_SUCCESS" ]; then
    if echo "$REDIRECT_SUCCESS" | grep -q "^/"; then
        SUCCESS_URL="${HOST}${REDIRECT_SUCCESS}"
    else
        SUCCESS_URL="$REDIRECT_SUCCESS"
    fi
    echo "Fetching success page: $SUCCESS_URL" | tee -a "$LOG_FILE"
    curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$SUCCESS_URL"
else
    echo "No redirect URL found after login post. Trying direct success path..." | tee -a "$LOG_FILE"
    curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "${HOST}/cp/guqs6n9d/success"
fi

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
#!/bin/bash
# SCRIPT_VERSION="1.2.0"

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

echo "Step 1: Detecting captive portal redirect URL..." | tee -a "$LOG_FILE"
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

echo "Step 2: Fetching the captive portal landing page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_FILE" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" "$REDIRECT_URL")
EFFECTIVE_URL=$(echo "$EFFECTIVE_URL" | tr -d '\015')
echo "Effective URL after redirect: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extract query string to preserve session / MAC parameters
QUERY_STRING=$(echo "$EFFECTIVE_URL" | grep -o '?.*')
echo "Extracted Query String: $QUERY_STRING" | tee -a "$LOG_FILE"

# Extract form action dynamically using POSIX sed
FORM_ACTION=$(sed -n 's/.*action="\([^"]*\)".*/\1/p' "$HTML_FILE" | head -n1)
if [ -z "$FORM_ACTION" ]; then
    FORM_ACTION="/login"
fi

if echo "$FORM_ACTION" | grep -q "^/"; then
    LOGIN_URL="${HOST}${FORM_ACTION}"
else
    LOGIN_URL="$FORM_ACTION"
fi

# Append query string safely
if [ -n "$QUERY_STRING" ]; then
    if echo "$LOGIN_URL" | grep -q "?"; then
        LOGIN_URL="${LOGIN_URL}&${QUERY_STRING#?}"
    else
        LOGIN_URL="${LOGIN_URL}${QUERY_STRING}"
    fi
fi
echo "Determined Login URL: $LOGIN_URL" | tee -a "$LOG_FILE"

# Extract and simulate click logs if present
CLICK_LOG_PATH=$(sed -n 's/.*data-click-logs="\([^"]*\)".*/\1/p' "$HTML_FILE" | head -n1)
if [ -n "$CLICK_LOG_PATH" ]; then
    CLICK_LOG_URL="${HOST}${CLICK_LOG_PATH}"
    echo "Step 3: Simulating click log 'load' event..." | tee -a "$LOG_FILE"
    curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
      -d "action=load" \
      -d "itemType=landing_page" \
      -d "itemValue=start" \
      "$CLICK_LOG_URL"

    echo "Step 4: Simulating click log 'connect' event..." | tee -a "$LOG_FILE"
    curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
      -d "itemType=landing_page" \
      -d "itemValue=connect" \
      -d "itemAdditional=oneclick" \
      "$CLICK_LOG_URL"
fi

echo "Step 5: Submitting login form and following redirect..." | tee -a "$LOG_FILE"
FINAL_URL=$(curl -k -L -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -d "login=oneclick" \
  -w "%{url_effective}" \
  -o /dev/null \
  "$LOGIN_URL")
FINAL_URL=$(echo "$FINAL_URL" | tr -d '\015')
echo "Final URL after submission: $FINAL_URL" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
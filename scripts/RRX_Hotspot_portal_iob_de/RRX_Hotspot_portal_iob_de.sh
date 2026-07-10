#!/bin/bash
# SCRIPT_VERSION="1.3.0"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Portal Login Process..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

perform_curl() {
    curl -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$@"
}

echo "Step 1: Capturing redirect URL from connectivity check..." | tee -a "$LOG_FILE"
# Capture initial redirect to identify the loginurl parameters provided by the gateway
REDIRECT_OUTPUT=$(curl -k -L -v -A "$USER_AGENT" -o /dev/null -w "%{url_effective}" "http://neverssl.com" 2>&1)
REDIRECT_URL=$(echo "$REDIRECT_OUTPUT" | grep "Location:" | tail -n 1 | sed 's/Location: //g' | tr -d '\015')
[ -z "$REDIRECT_URL" ] && REDIRECT_URL="http://portal.iob.de"

echo "Step 2: Accessing Landing Page to find 'Online gehen' link..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$REDIRECT_URL")

echo "Step 3: Extracting login trigger link..." | tee -a "$LOG_FILE"
LOGIN_TRIGGER=$(echo "$HTML_CONTENT" | sed -n 's/.*href="\([^"]*prelogin[^"]*\)".*/\1/p' | head -n 1)
if [ -z "$LOGIN_TRIGGER" ]; then
    LOGIN_TRIGGER="http://192.168.44.1/prelogin"
fi

echo "Step 4: Following prelogin trigger..." | tee -a "$LOG_FILE"
perform_curl -L "$LOGIN_TRIGGER"

echo "Step 5: Finalizing Hotsplots auth flow..." | tee -a "$LOG_FILE"
# The portal logic relies on the initial challenge/session parameters from the redirect
QUERY_PARAMS=$(echo "$REDIRECT_URL" | sed -n 's/.*\?\(.*\)/\1/p')
AUTH_URL="https://www.hotsplots.de/auth/login.php?$QUERY_PARAMS"
perform_curl -X POST -d "button=Login" "$AUTH_URL"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
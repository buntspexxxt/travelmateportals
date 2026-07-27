#!/bin/sh
# SCRIPT_VERSION="1.1.0"

COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT
LOG_FILE="/tmp/portal_login.log"

echo "Starting portal login sequence for WIFI_DB_wifi_bahn_de" | tee -a "$LOG_FILE"

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

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Dynamic domain resolution
TARGET_DOMAIN="wifi.bahn.de"
if ! nslookup "$TARGET_DOMAIN" >/dev/null 2>&1; then
    TARGET_DOMAIN="login.wifionice.de"
fi

echo "Using target domain: $TARGET_DOMAIN" | tee -a "$LOG_FILE"

# OpenSSL 3.0 has issues with some older gateway SSL/TLS configurations (unsafe legacy renegotiation).
# To mitigate this, we try to fetch via HTTP first to see if we can get redirected, 
# or if curl supports legacy negotiation, we run it. We also use -k to bypass certificate checks.
echo "Fetching initial portal page to obtain CSRF token..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT

# We try HTTP first, which might redirect to HTTPS but sometimes handles the handshake differently, or directly HTTPS.
curl -k -A "$UA" -c "$COOKIE_FILE" -d "" -o "$HTML_OUT" -m 15 "https://${TARGET_DOMAIN}/en/" >>"$LOG_FILE" 2>&1

# If that failed, we try login.wifionice.de
if [ ! -s "$HTML_OUT" ]; then
    echo "Primary fetch failed, trying alternative endpoint..." | tee -a "$LOG_FILE"
    curl -k -A "$UA" -c "$COOKIE_FILE" -d "" -o "$HTML_OUT" -m 15 "http://${TARGET_DOMAIN}/en/" >>"$LOG_FILE" 2>&1
fi

# Extract CSRF token from cookie file
CSRF_TOKEN=$(grep -i 'csrf' "$COOKIE_FILE" | tail -n 1 | awk '{print $7}')

# If not found in cookie, try extracting from the HTML content (just in case)
if [ -z "$CSRF_TOKEN" ]; then
    echo "CSRF token not found in cookies. Searching HTML..." | tee -a "$LOG_FILE"
    CSRF_TOKEN=$(sed -n 's/.*name="CSRFToken"[^"]*value="\([^"]*\)".*/\1/p' "$HTML_OUT")
fi

if [ -z "$CSRF_TOKEN" ]; then
    # Fallback: if we still can't find it, we extract any csrf token
    CSRF_TOKEN=$(grep -oE '[a-f0-9]{32,}' "$HTML_OUT" | head -n 1)
fi

if [ -z "$CSRF_TOKEN" ]; then
    echo "ERROR: Failed to extract CSRF token!" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracted CSRF Token: $CSRF_TOKEN" | tee -a "$LOG_FILE"

echo "Submitting login POST request..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    --data-urlencode "login=true" \
    --data-urlencode "CSRFToken=${CSRF_TOKEN}" \
    -m 15 "https://${TARGET_DOMAIN}/en/")

echo "POST response code: $?" | tee -a "$LOG_FILE"

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
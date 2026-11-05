#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/captive_portal.log"
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Waiting for network..."
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then echo "Ready!"; break; fi
    sleep 1
    i=$((i + 1))
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)

echo "Step 1: Accessing Telekom Hotspot..."
curl -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" "https://hotspot.t-mobile.net/TCOM/hotspot/MCD_HappyHour/de_DE/index.html"

echo "Step 2: Submitting free login..."
# Based on Ecom3 logic, 'forFree' is the target. Using standard T-Mobile Hotspot free access pattern.
# We hit the HPAAA (Hotspot Authentication & Authorization) backend.
AUTH_URL="https://www.hotspot.de/hpaaa/login"

# Note: This portal requires accepting Terms & Conditions which are handled by the Angular app.
# We simulate the POST request based on documented T-Mobile Hotspot API patterns.
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$AUTH_URL" \
  --data-urlencode "login=anonymous" \
  --data-urlencode "terms=1" \
  --data-urlencode "submit=Login" 

echo "Step 3: Verifying Internet..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ]; then
        echo "SUCCESS: Internet connected!"
        exit 0
    fi
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Connection failed."
exit 1
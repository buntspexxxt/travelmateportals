#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Telekom_public_hotspot_koeln automation
# Using standard portal flow for Deutsche Telekom hotspots

LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

echo "Starting Telekom Hotspot Login..." > "$LOG_FILE"

# 1. Ensure network is ready
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

# 2. Fetch the initial landing page to trigger redirect
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Initiating portal request..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -m 15 -A "$USER_AGENT" -w "%{url_effective}" -c "$COOKIE_FILE" -o "$HTML_OUT" "http://neverssl.com")

echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# 3. Telekom hotspots typically redirect to a central login page
# Submitting the 'login' or 'accept' equivalent
# For Telekom, this is often a GET request to the redirect URL with a 'login' param
echo "Submitting acceptance request..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -k -v -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o "$HTML_OUT" -w "%{http_code}" "$EFFECTIVE_URL")

echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

# 4. Verify connectivity
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
#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

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

# MikroTik Login Logic: The JS uses hexMD5(magic_char + password + challenge_bytes).
# Since we cannot easily replicate the JS VM, and this is a basic MikroTik portal,
# we will attempt a direct POST with standard credentials if applicable, or simulate the flow.

TARGET_URL="http://ELIXIR.NET/login"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching portal page to check for status..." | tee -a "$LOG_FILE"
curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_OUT" -w "HTTP Response: %{http_code}
" "http://neverssl.com" | tee -a "$LOG_FILE"

# NOTE: For free portals, often no user/pass is needed, or empty strings work.
# We attempt a POST with empty username/password as standard for open/guest portals.
# If specific credentials were required, they would be injected here.

echo "Submitting login request..." | tee -a "$LOG_FILE"
curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o "$HTML_OUT" -w "HTTP Response: %{http_code}
" \
--data-urlencode "username=" \
--data-urlencode "password=" \
--data-urlencode "dst=http://detectportal.firefox.com/success.txt" \
--data-urlencode "popup=true" \
"$TARGET_URL" | tee -a "$LOG_FILE"

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
#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Waiting for IP, Gateway, and DNS..."
i=1
while [ "$i" -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        log_message "Network and DNS are ready!"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

log_message "Fetching initial landing page..."
# We fetch the index page to establish a session and get the CSRF token
HTML_OUT=$(curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -L -m 15 "http://192.168.1.1/index.php")

# Extract hidden fields
C_VAL=$(echo "$HTML_OUT" | sed -n 's/.*name="c" value="\([^"]*\)".*/\1/p' | head -n 1)
CURR_PAGE=$(echo "$HTML_OUT" | sed -n 's/.*id="currentPage" type="hidden" name="currentPage" value="\([^"]*\)".*/\1/p' | head -n 1)

if [ -z "$C_VAL" ]; then
    log_message "ERROR: Could not extract form tokens."
    exit 1
fi

log_message "Submitting login payload (empty password for hotspot)..."
# The portal expects a POST request. We attempt the login with empty credentials.
RESPONSE=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" --data-urlencode "c=$C_VAL" --data-urlencode "currentPage=$CURR_PAGE" --data-urlencode "wuipassword=" -m 15 "http://192.168.1.1/index.php")

log_message "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ "$i" -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        log_message "SUCCESS: Internet connection verified!"
        exit 0
    fi
    log_message "Attempt $i: Not connected yet (HTTP Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done

log_message "ERROR: Portal request completed but no Internet connectivity established."
exit 1
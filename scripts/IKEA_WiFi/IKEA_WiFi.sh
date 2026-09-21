#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/ikea_wifi.log"
echo "Starting IKEA_WiFi login sequence" > "$LOG_FILE"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_OUT:-}"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

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

echo "Fetching redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -m 15 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%{url_effective}" -o "$HTML_OUT" "http://neverssl.com")

# IKEA Aruba portals require clicking 'Accept' on terms.
# The 'capture' parameter in the URL is a state token.
# We attempt a POST to the login endpoint indicated in the HTML.

echo "Submitting acceptance form..." | tee -a "$LOG_FILE"
# The Aruba portal usually expects a POST to the same path with 'accept_terms=1'
RESPONSE_CODE=$(curl -k -v -L -m 15 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    --data-urlencode "accept_terms=1" \
    -o "$HTML_OUT" -w "%{http_code}" "$REDIRECT_URL")

echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

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
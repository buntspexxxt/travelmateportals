#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/captive_portal.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT

exec > >(tee -a "$LOG_FILE") 2>&1

echo "Waiting for IP, Gateway, and DNS..."
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching landing page to obtain initial session cookies..."
curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" -m 15 "https://469.rdr.conn4.com/"

echo "Extracting WBS token from HTML..."
TOKEN=$(grep -o 'wbsToken = {[^}]*}' "$HTML_FILE" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to extract WBS token."
    exit 1
fi
echo "WBS Token extracted successfully."

echo "Submitting WBS token for authentication..."
# Based on the provided context, the site uses an internal JSON API to grant internet access.
# We attempt a POST to the identified portal host.
# Note: This portal requires JS interaction; we attempt to emulate the token submission.
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "https://469.rdr.conn4.com/wbs/de/roaming/return/" \
  --data-urlencode "token=$TOKEN" \
  -m 15

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{{http_code}}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established."
exit 1
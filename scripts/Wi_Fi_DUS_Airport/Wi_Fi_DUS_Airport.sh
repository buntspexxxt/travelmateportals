#!/bin/sh
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/wifi_login.log"
COOKIE_JAR="$(mktemp)"
HTML_OUT="$(mktemp)"
trap 'rm -f "${COOKIE_JAR}" "${HTML_OUT}"' EXIT

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1;
    then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
# Initial request to get the captive portal page
curl -k -L -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o "$HTML_OUT" -m 20 "http://neverssl.com"

echo "Attempting to trigger free access authentication..." | tee -a "$LOG_FILE"
# Based on analysis of T-Mobile Hotspot Suite portals:
# They typically post to the hpaaa endpoint with session parameters.
# Since this is a SPA, we attempt to hit the common free login grant URL.
curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X POST "https://www.hotspot.de/hpaaa/login/forFree" \
    -H "Content-Type: application/json" \
    -d '{"acceptTerms":true}' -m 15 \
    --stderr - >> "$LOG_FILE"
# Capture the response code for the above command
HTTP_STATUS=$(curl -k -s -o /dev/null -w '%{http_code}' -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 "https://www.hotspot.de/hpaaa/login/forFree")
echo "HTTP Status for login/forFree: $HTTP_STATUS" | tee -a "$LOG_FILE"

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "Successfully triggered free access." | tee -a "$LOG_FILE"
else
    echo "Failed to trigger free access. Status: $HTTP_STATUS" | tee -a "$LOG_FILE"
    # Continue with the next step as some portals might redirect even on non-200
fi

echo "Attempting to get grant for access..." | tee -a "$LOG_FILE"
# Some T-Mobile gateways require a secondary request to the 'grant' endpoint.
city='TD' # Defaulting to TD as seen in JS/HTML, could be more dynamic if needed
base_url="https://www.hotspot.de/hpaaa/login/grant"

curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X GET "$base_url" -m 15 \
    --stderr - >> "$LOG_FILE"
# Capture the response code for the above command
HTTP_STATUS=$(curl -k -s -o /dev/null -w '%{http_code}' -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 "$base_url")
echo "HTTP Status for login/grant: $HTTP_STATUS" | tee -a "$LOG_FILE"

if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "Warning: Failed to get grant for access. Status: $HTTP_STATUS. Continuing to check connectivity." | tee -a "$LOG_FILE"
fi


echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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

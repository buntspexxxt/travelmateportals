#!/bin/bash
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_log.txt"
echo "Starting portal login script..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

echo "Fetching portal index..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -L -c "$COOKIE_FILE" -o "$HTML_OUT" "http://neverssl.com" > /dev/null 2>&1

HTML=$(cat "$HTML_OUT")
AP_MAC=$(echo "$HTML" | sed -n 's/.*name="ap_mac" value="\([^"]*\)".*/\1/p' | head -n 1)
CLIENT_MAC=$(echo "$HTML" | sed -n 's/.*name="client_mac" value="\([^"]*\)".*/\1/p' | head -n 1)
WLAN_ID=$(echo "$HTML" | sed -n 's/.*name="wlan_id" value="\([^"]*\)".*/\1/p' | head -n 1)
URL_PARAM=$(echo "$HTML" | sed -n 's/.*name="url" value="\([^"]*\)".*/\1/p' | head -n 1)

echo "Submitting form with TOS accept..." | tee -a "$LOG_FILE"
# Based on the HTML, it expects 'tos=true' and 'auth_method=passphrase'
POST_DATA="ap_mac=$AP_MAC&client_mac=$CLIENT_MAC&wlan_id=$WLAN_ID&url=$(echo -n "$URL_PARAM" | sed 's/\//%2F/g; s/\:/%3A/g; s/\&/%26/g')&tos=true&auth_method=passphrase"

RESPONSE_CODE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" -w "%{http_code}" -o /dev/null "https://portal.eu.mist.com/logon")
echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
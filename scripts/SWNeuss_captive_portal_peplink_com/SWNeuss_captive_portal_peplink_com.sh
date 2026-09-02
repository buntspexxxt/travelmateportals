#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Waiting for network..." | tee -a "$LOG_FILE"
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

echo "Initializing Peplink session resume..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
# The JS logic performs an AJAX call to /cp/session/resume. We simulate the request parameters extracted from the HTML context.
# The checksum and other parameters are persistent in the provided HTML context.
RESUME_URL="https://guest7.ic.peplink.com/cp/session/resume"
POST_DATA="client_mac=D2:10:9F:2A:78:73&sn=2939-508B-F086&ssid=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&time=1788350181&cp_id=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&checksum=5889fe7db4d9cabaf3a8ce56d7123d8879548cfc"

echo "Attempting to resume session..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" "$RESUME_URL")
echo "Response: $RESPONSE" | tee -a "$LOG_FILE"

# If session resume returns data, we need to call the login endpoint
echo "Finalizing login..." | tee -a "$LOG_FILE"
LOGIN_URL="https://guest7.ic.peplink.com/cp/login"
# Constructing parameters based on the JS toResumeLogin logic
# We use the known parameters required for the login handshake
LOGIN_PARAMS="?resume=true&command=login&lang=en&sn=2939-508B-F086&ssid=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&ip=10.200.11.60&client_mac=D2:10:9F:2A:78:73&host_ip=192.168.50.1&host_mac=A8:C0:EA:52:CA:60&time=1788350181&cp_id=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&checksum=5889fe7db4d9cabaf3a8ce56d7123d8879548cfc"

curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "${LOGIN_URL}${LOGIN_PARAMS}" -o /dev/null

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
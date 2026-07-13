#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." | tee -a "$LOG_FILE"

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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

GW_IP=$(ip route | grep default | awk '{print $3}')
echo "Detected Gateway: $GW_IP" | tee -a "$LOG_FILE"

# 1. Fetch the initial session state from Peplink controller
# Parameters extracted from the provided HTML/JS logic
RESUME_URL="https://guest7.ic.peplink.com/cp/session/resume"
PARAMS="client_mac=82:4D:16:7F:D4:02&sn=2939-5050-2D30&ssid=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&time=1783790708&cp_id=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&checksum=bb0a27b29e6d86f5df54d02cdc2dd1fb020ec8f7&_=1783790708"

echo "Resuming session..." | tee -a "$LOG_FILE"
RESUME_OUT=$(curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -G -d "$PARAMS" "$RESUME_URL")
echo "Resume Response: $RESUME_OUT" | tee -a "$LOG_FILE"

# 2. Handle the 'Connect' page interaction
# The HTML indicates a form-less button trigger that calls makeResumeLoginCall
# We simulate this by calling the /cp/login endpoint directly with the required parameters
LOGIN_URL="https://guest7.ic.peplink.com/cp/login"
LOGIN_PARAMS="resume=true&command=login&sn=2939-5050-2D30&ssid=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&client_mac=82:4D:16:7F:D4:02&checksum=bb0a27b29e6d86f5df54d02cdc2dd1fb020ec8f7&time=1783790708"

echo "Executing login trigger..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -G -d "$LOGIN_PARAMS" "$LOGIN_URL" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
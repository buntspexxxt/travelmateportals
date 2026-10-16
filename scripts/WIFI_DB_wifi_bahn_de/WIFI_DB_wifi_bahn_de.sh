#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Starting Deutsche Bahn Wi-Fi login sequence" | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup wifi.bahn.de >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
DOMAIN="wifi.bahn.de"

echo "Attempting CNA API logon (JSON)..." | tee -a "$LOG_FILE"
# Added --ciphers DEFAULT@SECLEVEL=0 to handle 'unsafe legacy renegotiation' error
curl -k -v -A "$UA" -m 15 --ciphers DEFAULT@SECLEVEL=0 -H "Content-Type: application/json" -H "X-Requested-With: XMLHttpRequest" -H "X-Csrf-Token: csrf" -d "{}" "https://$DOMAIN/cna/logon" >>"$LOG_FILE" 2>&1

echo "Attempting legacy portal authentication..." | tee -a "$LOG_FILE"
curl -k -v -A "$UA" -m 15 --ciphers DEFAULT@SECLEVEL=0 -c "$COOKIE_FILE" -o /dev/null "https://$DOMAIN/en/" >>"$LOG_FILE" 2>&1

TOKEN=$(grep -i 'csrf' "$COOKIE_FILE" | tail -n 1 | awk '{print $7}' | tr -d '\015')
if [ -n "$TOKEN" ]; then
    echo "Found token, submitting POST..." | tee -a "$LOG_FILE"
    curl -k -v -A "$UA" -m 15 --ciphers DEFAULT@SECLEVEL=0 -b "$COOKIE_FILE" -H "Cookie: csrf=$TOKEN" --data-urlencode "login=true" --data-urlencode "CSRFToken=$TOKEN" "https://$DOMAIN/en/" >>"$LOG_FILE" 2>&1
else
    echo "Error: Could not extract CSRF token." | tee -a "$LOG_FILE"
    exit 1
fi

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
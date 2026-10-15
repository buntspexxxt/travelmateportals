#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Starting Deutsche Bahn Wi-Fi login sequence" | tee -a "$LOG_FILE"

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup wifi.bahn.de >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
    i=$((i + 1))
done

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
DOMAIN="wifi.bahn.de"

echo "Attempting CNA API logon..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$UA" -H "Content-Type: application/json" -H "X-Requested-With: XMLHttpRequest" -H "X-Csrf-Token: csrf" -d "{}" "https://$DOMAIN/cna/logon" 2>&1)
echo "$RESPONSE" | grep -q "success" && echo "CNA Success" | tee -a "$LOG_FILE" && exit 0

echo "CNA failed, attempting legacy portal authentication..." | tee -a "$LOG_FILE"
curl -k -v -A "$UA" -c "$COOKIE_FILE" -o /dev/null "https://$DOMAIN/en/" >>"$LOG_FILE" 2>&1

TOKEN=$(grep -i 'csrf' "$COOKIE_FILE" | tail -n 1 | awk '{print $7}' | tr -d '\015')
if [ -n "$TOKEN" ]; then
    echo "Found token, submitting POST..." | tee -a "$LOG_FILE"
    curl -k -v -A "$UA" -b "$COOKIE_FILE" -H "Cookie: csrf=$TOKEN" --data-urlencode "login=true" --data-urlencode "CSRFToken=$TOKEN" "https://$DOMAIN/en/" >>"$LOG_FILE" 2>&1
else
    echo "Error: Could not extract CSRF token." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Verifying connectivity..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "http://connectivitycheck.gstatic.com/generate_204")
    [ "$CODE" = "204" ] && echo "Connected!" && exit 0
    sleep 4
    i=$((i + 1))
done
exit 1
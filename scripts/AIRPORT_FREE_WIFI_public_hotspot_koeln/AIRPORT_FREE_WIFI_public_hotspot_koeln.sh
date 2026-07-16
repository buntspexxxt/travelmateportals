#!/bin/sh
# SCRIPT_VERSION="1.4.0"

trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting portal login sequence..." | tee -a "$LOG_FILE"

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
    i=$((i + 1))
done

echo "Step 1: Fetching portal landing page..." | tee -a "$LOG_FILE"
curl -m 15 -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" "https://public.hotspot.koeln/cp/guqs6n9d" >/dev/null 2>&1

echo "Step 2: Submitting form..." | tee -a "$LOG_FILE"
# Based on analysis, the form requires the checkbox field 'customControlValidation1' to be 'on'.
# The form action is fixed as /login.
RESPONSE=$(curl -m 15 -k -L -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  --data-urlencode "login=oneclick" \
  --data-urlencode "customControlValidation1=on" \
  "https://public.hotspot.koeln/login" 2>&1)

echo "HTTP Response captured. Verifying..." | tee -a "$LOG_FILE"

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
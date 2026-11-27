#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE=/tmp/portal_login.log
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Starting Nordsee Portal Login..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP
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

# 2. Fetching landing page to identify state
HTML_OUT=$(mktemp)
echo "Fetching portal page..." | tee -a "$LOG_FILE"
curl -k -v -L -m 15 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -c "$COOKIE_FILE" "http://guests.nordsee.com/index.php?zone=gast" > "$HTML_OUT" 2>&1

# 3. Extract hidden fields
REDIRECT_URL=$(sed -n 's/.*name="redirurl" value="\([^"]*\)".*/\1/p' "$HTML_OUT")
ZONE=$(sed -n 's/.*name="zone" value="\([^"]*\)".*/\1/p' "$HTML_OUT")
ORIGIN=$(sed -n 's/.*name="origin" value="\([^"]*\)".*/\1/p' "$HTML_OUT")
LANG=$(sed -n 's/.*name="lang" value="\([^"]*\)".*/\1/p' "$HTML_OUT")

# 4. Perform POST request
# Portal requires filling fields: firstname, lastname, email + checkbox 'wlan'
echo "Submitting login form with data..." | tee -a "$LOG_FILE"
curl -k -v -m 15 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  --data-urlencode "firstname=Gast" \
  --data-urlencode "lastname=Nordsee" \
  --data-urlencode "email=guest@nordsee.com" \
  --data-urlencode "wlan=on" \
  --data-urlencode "redirurl=$REDIRECT_URL" \
  --data-urlencode "zone=$ZONE" \
  --data-urlencode "origin=$ORIGIN" \
  --data-urlencode "lang=$LANG" \
  --data-urlencode "accept=Absenden" \
  "http://guests.nordsee.com/send_api_newsletter.php" 2>&1 | tee -a "$LOG_FILE"

# 5. Connectivity Check
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds."
exit 1
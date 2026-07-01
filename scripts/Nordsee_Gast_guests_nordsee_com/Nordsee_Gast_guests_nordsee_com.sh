#!/bin/bash
LOG_FILE=/tmp/portal_login.log
echo "Starting Nordsee Portal Login..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# 2. Get the portal page to extract hidden fields
echo "Fetching portal page..." | tee -a "$LOG_FILE"
PORTAL_PAGE=$(curl -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" http://guests.nordsee.com/index.php?zone=gast 2>&1)
echo "Portal Page Fetch Complete." | tee -a "$LOG_FILE"

# 3. Extract hidden fields using sed
echo "Extracting hidden form fields..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(echo "$PORTAL_PAGE" | sed -n 's/.*name="redirurl" value="\([^"]*\)".*/\1/p')
ZONE=$(echo "$PORTAL_PAGE" | sed -n 's/.*name="zone" value="\([^"]*\)".*/\1/p')
ORIGIN=$(echo "$PORTAL_PAGE" | sed -n 's/.*name="origin" value="\([^"]*\)".*/\1/p')
LANG=$(echo "$PORTAL_PAGE" | sed -n 's/.*name="lang" value="\([^"]*\)".*/\1/p')

# 4. Perform POST request
# WARNING: Portal requires Firstname, Lastname, and Email. Providing dummy data for automation.
echo "Submitting login form..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \\
  -d "firstname=Guest&lastname=User&email=guest%40example.com&wlan=on&accept=Absenden&redirurl=${REDIRECT_URL}&zone=${ZONE}&origin=${ORIGIN}&lang=${LANG}" \\
  http://guests.nordsee.com/send_api_newsletter.php 2>&1)

echo "HTTP Response Received: $RESPONSE" | tee -a "$LOG_FILE"

# 5. Connectivity Check
echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." && exit 0 || echo "Error: No internet access." && exit 1
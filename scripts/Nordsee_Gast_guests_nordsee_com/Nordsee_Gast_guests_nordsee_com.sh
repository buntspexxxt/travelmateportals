#!/bin/bash
LOG_FILE=/tmp/portal_login.log
echo "Starting Nordsee Portal Login..." | tee -a \$LOG_FILE

# 1. Wait for DHCP
echo "Waiting for DHCP (IP & Gateway)..." | tee -a \$LOG_FILE
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a \$LOG_FILE
        sleep 6
        break
    fi
    sleep 1
done

# 2. Get the portal page to extract hidden fields
echo "Fetching portal page..." | tee -a \$LOG_FILE
PORTAL_HTML=$(curl -k -k -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" http://guests.nordsee.com/index.php?zone=gast 2>&1)

# 3. Extract hidden fields dynamically
echo "Extracting hidden form fields..." | tee -a \$LOG_FILE
REDIRECT_URL=$(echo "\$PORTAL_HTML" | sed -n 's/.*name="redirurl" value="\([^"]*\)".*/\1/p')
ZONE=$(echo "\$PORTAL_HTML" | sed -n 's/.*name="zone" value="\([^"]*\)".*/\1/p')
ORIGIN=$(echo "\$PORTAL_HTML" | sed -n 's/.*name="origin" value="\([^"]*\)".*/\1/p')
LANG=$(echo "\$PORTAL_HTML" | sed -n 's/.*name="lang" value="\([^"]*\)".*/\1/p')

# 4. Perform POST request
# According to hint: User only needs to accept terms (wlan=on), no email/name required if not forced by JS logic.
# Submitting with wlan=on for Terms acceptance.
echo "Submitting login form..." | tee -a \$LOG_FILE
RESPONSE=$(curl -k -k -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -d "wlan=on&accept=Absenden&redirurl=\${REDIRECT_URL}&zone=\${ZONE}&origin=\${ORIGIN}&lang=\${LANG}" \
  http://guests.nordsee.com/send_api_newsletter.php 2>&1)

echo "HTTP Response Received: \$RESPONSE" | tee -a \$LOG_FILE

# 5. Connectivity Check
echo "Checking connectivity..." | tee -a \$LOG_FILE
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." && exit 0 || echo "Error: No internet access." && exit 1
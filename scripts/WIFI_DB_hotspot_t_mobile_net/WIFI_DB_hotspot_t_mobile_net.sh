#!/bin/bash
LOG_FILE="/tmp/hotspot_login.log"
COOKIE_JAR="/tmp/telekom_cookies.txt"
echo "$(date): Starting login script for Telekom Hotspot..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP (IP & Gateway)
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# Check if already online
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "Already online. Exiting." | tee -a "$LOG_FILE"
    exit 0
fi

# 2. Get the redirect and populate cookies
echo "Fetching redirect page and generating cookies..." | tee -a "$LOG_FILE"
rm -f "$COOKIE_JAR"
# We curl a non-secure URL to trigger the captive portal redirect
# -L: Follow redirects so we hit the actual landing page on hotspot.t-mobile.net
# -c: Write cookies to cookie jar
# -b: Send cookies (read from same cookie jar)
# -k: Insecure (ignore certificate issues if gateway serves self-signed)
# --connect-timeout: Limit wait time
curl -s -L -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
     --connect-timeout 10 \
     --user-agent "Mozilla/5.0 (Linux x86_64; rv:109.0) Gecko/20100101 Firefox/119.0" \
     "http://detectportal.firefox.com/success.txt" > /dev/null

if [ ! -f "$COOKIE_JAR" ] || ! grep -q "JSESSIONID" "$COOKIE_JAR"; then
    echo "Error: Did not receive JSESSIONID cookie. Redirect might have failed." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Cookies obtained successfully." | tee -a "$LOG_FILE"

# 3. Post to freeLogin endpoint
echo "Submitting freeLogin activation..." | tee -a "$LOG_FILE"
# Send the POST request to wlan/rest/freeLogin
# We must use the cookies obtained in step 2
curl -s -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -k -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     --connect-timeout 10 \
     -H "Content-Type: application/json" \
     -H "Referer: https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     --user-agent "Mozilla/5.0 (Linux x86_64; rv:109.0) Gecko/20100101 Firefox/119.0" \
     --data '{"rememberMe":true}' | tee -a "$LOG_FILE"

echo "" >> "$LOG_FILE"
rm -f "$COOKIE_JAR"

# 4. Verification check
echo "Verifying connection..." | tee -a "$LOG_FILE"
sleep 3
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "Login successful! Internet is active." | tee -a "$LOG_FILE"
    exit 0
else
    echo "Login failed. Internet is still offline." | tee -a "$LOG_FILE"
    exit 1
fi

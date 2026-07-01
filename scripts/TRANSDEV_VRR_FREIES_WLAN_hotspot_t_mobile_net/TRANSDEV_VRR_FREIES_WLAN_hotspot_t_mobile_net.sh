#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="/tmp/telekom_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting login script for Transdev VRR Telekom Hotspot..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP (IP & Gateway)
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
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

RESPONSE=$(curl -k -k -v -L -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
     --connect-timeout 15      --user-agent "$USER_AGENT" \
     "http://neverssl.com" 2>&1)

if [ ! -f "$COOKIE_JAR" ]; then
    echo "Warning: No cookie jar file created." | tee -a "$LOG_FILE"
fi

REDIRECT_URL=$(echo "$RESPONSE" | grep -i "< Location:" | tail -n 1 | sed -n "s/.*Location: //p" | tr -d '\r')
echo "Redirect URL found: $REDIRECT_URL" | tee -a "$LOG_FILE"

# 3. Post to freeLogin endpoint
echo "Submitting freeLogin activation..." | tee -a "$LOG_FILE"
LOGIN_RESPONSE=$(curl -k -k -v -k -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     --connect-timeout 15 \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -H "Referer: https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     --user-agent "$USER_AGENT" \
     -d "button=Login&UserName=&Password=&FNAME=0" 2>&1)

echo "Response from freeLogin: $LOGIN_RESPONSE" | tee -a "$LOG_FILE"

# 4. Verification check
echo "Verifying connection..." | tee -a "$LOG_FILE"
sleep 5
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "Login successful! Internet is active." | tee -a "$LOG_FILE"
    rm -f "$COOKIE_JAR"
    exit 0
else
    echo "Trying fallback simple JSON POST..." | tee -a "$LOG_FILE"
    curl -k -k -s -k -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
         -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
         -H "Content-Type: application/json" \
         --user-agent "$USER_AGENT" \
         -d '{"rememberMe":true}' > /dev/null
    sleep 5
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        echo "Login successful on JSON fallback! Internet is active." | tee -a "$LOG_FILE"
        rm -f "$COOKIE_JAR"
        exit 0
    fi
    echo "Login failed. Internet is still offline." | tee -a "$LOG_FILE"
    rm -f "$COOKIE_JAR"
    exit 1
fi

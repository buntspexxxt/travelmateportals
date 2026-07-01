#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_JAR="/tmp/db_cookies.txt"
HTML_PAGE="/tmp/db_landing.html"

echo "Starting login process for WIFI_DB_wifi_bahn_de" | tee -a "$LOG_FILE"

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

# Try accessing neverssl.com first to initialize the portal redirect
echo "Accessing neverssl.com to trigger redirect..." | tee -a "$LOG_FILE"
curl -k -k -s -L -k -A "$USER_AGENT" -o /dev/null "http://neverssl.com"

# 2. Fetch the initial landing page and save cookies
echo "Fetching landing page from login.wifionice.de..." | tee -a "$LOG_FILE"
rm -f "$COOKIE_JAR" "$HTML_PAGE"

curl -k -k -s -k -L -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
     "http://login.wifionice.de/de/" > "$HTML_PAGE"

if [ ! -s "$HTML_PAGE" ] || grep -q "failed" "$HTML_PAGE"; then
    echo "Fallback: Fetching from wifi.bahn.de..." | tee -a "$LOG_FILE"
    curl -k -k -s -k -L -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
         "https://wifi.bahn.de/" > "$HTML_PAGE"
fi

# 3. Extract CSRF token from HTML page or cookies
TOKEN=""
if [ -f "$HTML_PAGE" ]; then
    TOKEN=$(sed -n 's/.*name="CSRFToken" value="\([^"/]*\)".*/\1/p' "$HTML_PAGE" | head -n 1)
    if [ -z "$TOKEN" ]; then
        TOKEN=$(sed -n 's/.*CSRFToken" value="\([^"/]*\)".*/\1/p' "$HTML_PAGE" | head -n 1)
    fi
    if [ -z "$TOKEN" ]; then
        TOKEN=$(sed -n 's/.*CSRFToken=\([^"& ]*\).*/\1/p' "$HTML_PAGE" | head -n 1)
    fi
fi

if [ -z "$TOKEN" ] && [ -f "$COOKIE_JAR" ]; then
    TOKEN=$(grep "CSRFToken" "$COOKIE_JAR" | awk '{print $NF}')
fi

echo "Extracted CSRFToken: $TOKEN" | tee -a "$LOG_FILE"

# 4. Perform POST login
echo "Submitting terms and conditions to login.wifionice.de..." | tee -a "$LOG_FILE"
LOGIN_RESPONSE=$(curl -k -k -s -k -L -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -X POST \
     -d "login=true&CSRFToken=${TOKEN}&connect=" \
     "http://login.wifionice.de/de/")

echo "Response length: ${#LOGIN_RESPONSE}" | tee -a "$LOG_FILE"

# Try fallback post to wifi.bahn.de/en if wifionice failed
sleep 3
if ! ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "Fallback login to wifi.bahn.de..." | tee -a "$LOG_FILE"
    curl -k -k -s -k -L -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
         -X POST \
         -d "login=true&CSRFToken=${TOKEN}&connect=" \
         "https://wifi.bahn.de/" > /dev/null
fi

# 5. Connectivity check
echo "Finalizing connectivity check..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >/dev/null && { echo "Success: Internet reached."; rm -f "$COOKIE_JAR" "$HTML_PAGE"; exit 0; } || {
    echo "Failed: Connectivity not established." | tee -a "$LOG_FILE"
    rm -f "$COOKIE_JAR" "$HTML_PAGE"
    exit 1
}

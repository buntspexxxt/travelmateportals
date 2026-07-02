#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies.txt"

echo "Starting ALDI WiFi Login Script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Detecting captive portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_RAW=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null http://detectportal.firefox.com/success.txt 2>&1)

LANDING_URL=$(echo "$REDIRECT_RAW" | grep -i "< Location:" | head -n1 | sed -n 's/.*[Ll]ocation: //p' | tr -d '\r' | xargs)

if [ -z "$LANDING_URL" ]; then
    echo "Firefox detection failed. Trying fallback Google connectivity check..." | tee -a "$LOG_FILE"
    REDIRECT_RAW=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null http://google.com/generate_204 2>&1)
    LANDING_URL=$(echo "$REDIRECT_RAW" | grep -i "Location:" | head -n1 | sed -n 's/.*[Ll]ocation: //p' | tr -d '\r' | xargs)
fi

if [ -z "$LANDING_URL" ]; then
    echo "CRITICAL: Could not detect captive portal redirect URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Captive portal redirect detected: $LANDING_URL" | tee -a "$LOG_FILE"

# Dynamically extract Base URL (e.g. https://eu.network-auth.com/splash/bs-qtcsd.7.1097)
BASE_URL=$(echo "$LANDING_URL" | sed 's/\/[?].*//' | sed 's/\/$//')
echo "Dynamic Base URL: $BASE_URL" | tee -a "$LOG_FILE"

echo "Requesting initial splash page to capture session cookies..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null "$LANDING_URL"

echo "Requesting grant authorization via HEAD request with XMLHttpRequest and Referer..." | tee -a "$LOG_FILE"
RESPONSE_HEADERS=$(curl -v -I -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -H "X-Requested-With: XMLHttpRequest" -H "Referer: $LANDING_URL" "$LANDING_URL" 2>&1)

CONTINUE_URL=$(echo "$RESPONSE_HEADERS" | grep -i "Continue-Url" | head -n1 | sed -n 's/.*[Cc]ontinue-[Uu]rl: //p' | tr -d '\r' | xargs)

if [ -z "$CONTINUE_URL" ]; then
    echo "HEAD request did not return Continue-Url. Trying GET request with header dump..." | tee -a "$LOG_FILE"
    RESPONSE_HEADERS=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -H "X-Requested-With: XMLHttpRequest" -H "Referer: $LANDING_URL" "$LANDING_URL" -D - -o /dev/null 2>&1)
    CONTINUE_URL=$(echo "$RESPONSE_HEADERS" | grep -i "Continue-Url" | head -n1 | sed -n 's/.*[Cc]ontinue-[Uu]rl: //p' | tr -d '\r' | xargs)
fi

if [ -z "$CONTINUE_URL" ]; then
    echo "WARNING: Failed to extract Continue-Url from headers. Using default fallback..." | tee -a "$LOG_FILE"
    CONTINUE_URL="https%3A%2F%2Fwww.aldi-sued.de"
fi

GRANT_URL="$BASE_URL/grant?continue_url=$CONTINUE_URL"
echo "Submitting grant authorization to: $GRANT_URL" | tee -a "$LOG_FILE"
GRANT_RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -H "Referer: $LANDING_URL" "$GRANT_URL" 2>&1)

echo "--- Grant Response ---" | tee -a "$LOG_FILE"
echo "$GRANT_RESPONSE" | tee -a "$LOG_FILE"
echo "----------------------" | tee -a "$LOG_FILE"

echo "Waiting 5 seconds before checking connectivity..." | tee -a "$LOG_FILE"
sleep 5

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
if ping -c 3 8.8.8.8 >/dev/null; then
    echo "Connectivity confirmed. Success!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "Connectivity check failed." | tee -a "$LOG_FILE"
    exit 1
fi
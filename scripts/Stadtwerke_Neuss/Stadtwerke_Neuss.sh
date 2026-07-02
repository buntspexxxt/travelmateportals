#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/hotsplots_cookies.txt"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching initial portal page to extract hidden fields..." | tee -a "$LOG_FILE"
HTML=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" "http://www.google.com/" 2>&1)
LOCATION=$(echo "$HTML" | sed -n 's/.*Location: \(.*\)/\1/p' | tr -d '\\r')

if [ -z "$LOCATION" ]; then
    echo "No redirect found. Already logged in or network error."
    exit 0
fi

echo "Redirecting to: $LOCATION"
PORTAL_PAGE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LOCATION")

echo "Extracting dynamic form parameters..."
CHALLENGE=$(echo "$PORTAL_PAGE" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$PORTAL_PAGE" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$PORTAL_PAGE" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
USERURL=$(echo "$PORTAL_PAGE" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$PORTAL_PAGE" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

if [ -z "$CHALLENGE" ]; then
    echo "Failed to extract challenge. Portal structure might have changed." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting login request..."
POST_DATA="haveTerms=1&termsOK=on&button=kostenlos+einloggen&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&userurl=$USERURL&myLogin=agb&ll=de&nasid=$NASID&custom=1"
RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -d "$POST_DATA" "https://www.hotsplots.de/auth/login.php")

echo "Verifying connectivity..."
ping -c 3 8.8.8.8 >/dev/null && (echo "Login successful!" && exit 0) || (echo "Login failed or no internet access." && exit 1)
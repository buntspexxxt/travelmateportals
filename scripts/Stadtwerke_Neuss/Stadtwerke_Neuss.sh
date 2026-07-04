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

check_quota() {
    echo "Checking quota / status..." | tee -a "$LOG_FILE"
    STATUS_HTML=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" "https://www.hotsplots.de/auth/login.php" 2>&1)
    LIMIT_INFO=$(echo "$STATUS_HTML" | sed -n 's/.*\([0-9]\{1,\}[[:space:]]*MB\).*/\1/p' | head -n 5)
    if [ -n "$LIMIT_INFO" ]; then
        echo "Quota / Limit information: $LIMIT_INFO" | tee -a "$LOG_FILE"
    else
        echo "No explicit quota information found on the status page." | tee -a "$LOG_FILE"
    fi
}

echo "Step 1: Attempting to trigger redirection by visiting http://neverssl.com" | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" "http://neverssl.com" 2>&1)
echo "Trigger response captured." | tee -a "$LOG_FILE"

LOCATION=$(echo "$RESPONSE" | sed -n 's/.*[Ll]ocation: \([^ ]*\).*/\1/p' | tr -d '\r' | head -n 1)

if [ -z "$LOCATION" ]; then
    echo "No redirection detected. Checking internet connectivity directly..." | tee -a "$LOG_FILE"
    if ping -c 3 8.8.8.8 >/dev/null; then
        echo "Already online!" | tee -a "$LOG_FILE"
        check_quota
        exit 0
    else
        echo "Not online, but no redirect Location header found. Exiting." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

echo "Step 2: Accessing the captive portal URL: $LOCATION" | tee -a "$LOG_FILE"
HTML=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LOCATION" 2>&1)

echo "Step 3: Extracting dynamic parameters from HTML and redirection URL..." | tee -a "$LOG_FILE"
CHALLENGE=$(echo "$HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
[ -z "$CHALLENGE" ] && CHALLENGE=$(echo "$LOCATION" | sed -n 's/.*[?&]challenge=\([^&]*\).*/\1/p')

UAMIP=$(echo "$HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
[ -z "$UAMIP" ] && UAMIP=$(echo "$LOCATION" | sed -n 's/.*[?&]uamip=\([^&]*\).*/\1/p')

UAMPORT=$(echo "$HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
[ -z "$UAMPORT" ] && UAMPORT=$(echo "$LOCATION" | sed -n 's/.*[?&]uamport=\([^&]*\).*/\1/p')

USERURL=$(echo "$HTML" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p')
[ -z "$USERURL" ] && USERURL=$(echo "$LOCATION" | sed -n 's/.*[?&]userurl=\([^&]*\).*/\1/p')

NASID=$(echo "$HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')
[ -z "$NASID" ] && NASID=$(echo "$LOCATION" | sed -n 's/.*[?&]nasid=\([^&]*\).*/\1/p')

MYLOGIN=$(echo "$HTML" | sed -n 's/.*name="myLogin" value="\([^"]*\)".*/\1/p')
[ -z "$MYLOGIN" ] && MYLOGIN="agb"

LL=$(echo "$HTML" | sed -n 's/.*name="ll" value="\([^"]*\)".*/\1/p')
[ -z "$LL" ] && LL="de"

CUSTOM=$(echo "$HTML" | sed -n 's/.*name="custom" value="\([^"]*\)".*/\1/p')
[ -z "$CUSTOM" ] && CUSTOM="1"

HAVETERMS=$(echo "$HTML" | sed -n 's/.*name="haveTerms" value="\([^"]*\)".*/\1/p')
[ -z "$HAVETERMS" ] && HAVETERMS="1"

echo "Extracted parameters:"
echo "  CHALLENGE: $CHALLENGE"
echo "  UAMIP: $UAMIP"
echo "  UAMPORT: $UAMPORT"
echo "  USERURL: $USERURL"
echo "  NASID: $NASID"

if [ -z "$CHALLENGE" ]; then
    echo "CRITICAL: Failed to extract 'challenge' parameter. Cannot login." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Step 4: Submitting terms acceptance form with login POST..." | tee -a "$LOG_FILE"
POST_DATA="haveTerms=${HAVETERMS}&termsOK=on&button=kostenlos+einloggen&challenge=${CHALLENGE}&uamip=${UAMIP}&uamport=${UAMPORT}&userurl=${USERURL}&myLogin=${MYLOGIN}&ll=${LL}&nasid=${NASID}&custom=${CUSTOM}"

# Use -L to allow curl to follow the redirect chain back to the local gateway authentication endpoint
AUTH_RESPONSE=$(curl -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" "https://www.hotsplots.de/auth/login.php" 2>&1)

echo "Auth Response Captured." | tee -a "$LOG_FILE"

echo "Step 5: Verifying network connectivity..." | tee -a "$LOG_FILE"
sleep 3
if ping -c 3 8.8.8.8 >/dev/null; then
    echo "SUCCESS: Internet connection established!" | tee -a "$LOG_FILE"
    check_quota
    exit 0
else
    echo "FAILURE: Could not ping 8.8.8.8 after submitting credentials." | tee -a "$LOG_FILE"
    exit 1
fi
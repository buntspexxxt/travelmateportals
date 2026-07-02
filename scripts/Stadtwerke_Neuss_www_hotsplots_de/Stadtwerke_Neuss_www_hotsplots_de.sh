#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting Hotsplots login script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

rm -f /tmp/cookies.txt /tmp/login_page.html

echo "Triggering portal redirect..." | tee -a "$LOG_FILE"
# Using -v to capture headers for redirect URL extraction
REDIRECT_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt "http://neverssl.com" 2>&1)
REDIRECT_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*Location: //p' | tr -d '\r' | head -n 1)

if [ -z "$REDIRECT_URL" ]; then
    echo "No redirect found. Checking connectivity..." | tee -a "$LOG_FILE"
else
    echo "Redirect detected: $REDIRECT_URL" | tee -a "$LOG_FILE"
    curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt "$REDIRECT_URL" > /tmp/login_page.html

    echo "Parsing hidden inputs from login page..." | tee -a "$LOG_FILE"
    get_val() { grep -i "name="$1"" /tmp/login_page.html | sed -n 's/.*value="\([^"]*\)".*/\1/p' | head -n 1; }
    
    CHALLENGE=$(get_val "challenge")
    UAMIP=$(get_val "uamip")
    UAMPORT=$(get_val "uamport")
    USERURL=$(get_val "userurl")
    NASID=$(get_val "nasid")
    LL=$(get_val "ll")
    CUSTOM=$(get_val "custom")
    MYLOGIN="agb"

    # The form expects termsOK=on and haveTerms=1
    POST_DATA="haveTerms=1&termsOK=on&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&userurl=$USERURL&myLogin=$MYLOGIN&ll=$LL&nasid=$NASID&custom=$CUSTOM&button=kostenlos+einloggen"

    echo "Submitting login form to Hotsplots..." | tee -a "$LOG_FILE"
    curl -L -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -d "$POST_DATA" "https://www.hotsplots.de/auth/login.php" 2>&1 | tee -a "$LOG_FILE"
fi

sleep 5
echo "Final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && { echo "Login success!" | tee -a "$LOG_FILE"; exit 0; } || { echo "Login failed." | tee -a "$LOG_FILE"; exit 1; }
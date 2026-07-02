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
REDIRECT_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt "http://neverssl.com" 2>&1)

REDIRECT_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*Location: //p' | tr -d '\r' | head -n 1)

if [ -z "$REDIRECT_URL" ]; then
    echo "No redirect found. Testing connectivity..." | tee -a "$LOG_FILE"
else
    echo "Redirecting to: $REDIRECT_URL" | tee -a "$LOG_FILE"
    echo "Downloading portal HTML..." | tee -a "$LOG_FILE"
    curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt "$REDIRECT_URL" > /tmp/login_page.html

    get_input_value() {
        grep -i "name="$1"" /tmp/login_page.html | sed -n 's/.*value="\([^"]*\)".*/\1/p' | head -n 1
    }

    CHALLENGE=$(get_input_value "challenge")
    UAMIP=$(get_input_value "uamip")
    UAMPORT=$(get_input_value "uamport")
    USERURL=$(get_input_value "userurl")
    LL=$(get_input_value "ll")
    NASID=$(get_input_value "nasid")
    CUSTOM=$(get_input_value "custom")

    # Required fields for Hotsplots login form
    POST_DATA="haveTerms=1&termsOK=on&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&userurl=$USERURL&myLogin=agb&ll=$LL&nasid=$NASID&custom=$CUSTOM&button=kostenlos+einloggen"

    echo "Submitting login form to Hotsplots..." | tee -a "$LOG_FILE"
    curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -d "$POST_DATA" "https://www.hotsplots.de/auth/login.php" 2>&1 | tee -a "$LOG_FILE"
fi

sleep 5
echo "Verifying connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && { echo "Login successful!" | tee -a "$LOG_FILE"; exit 0; } || { echo "Login failed." | tee -a "$LOG_FILE"; exit 1; }
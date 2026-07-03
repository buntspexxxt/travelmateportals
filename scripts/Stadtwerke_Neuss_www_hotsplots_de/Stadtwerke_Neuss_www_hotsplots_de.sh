#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting Stadtwerke Neuss (Hotsplots) login script..." | tee -a "$LOG_FILE"

# Wait for network interface
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
REDIRECT_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*[Ll]ocation: //p' | tr -d '\r' | head -n 1)

if [ -z "$REDIRECT_URL" ]; then
    echo "Primary redirect detection failed. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Fetching login page..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt "$REDIRECT_URL" > /tmp/login_page.html

get_val() {
    grep -i "name="$1"" /tmp/login_page.html | sed -n 's/.*value="\([^"]*\)".*/\1/p' | head -n 1
}

# Extracting all required fields dynamically
CHALLENGE=$(get_val "challenge")
UAMIP=$(get_val "uamip")
UAMPORT=$(get_val "uamport")
USERURL=$(get_val "userurl")
NASID=$(get_val "nasid")
LL=$(get_val "ll")
CUSTOM=$(get_val "custom")

echo "Submitting terms acceptance via POST..." | tee -a "$LOG_FILE"
# The form requires termsOK=on to pass the validation logic
curl -v -A "$USER_AGENT" \
    -b /tmp/cookies.txt -c /tmp/cookies.txt \
    -d "haveTerms=1" \
    -d "termsOK=on" \
    -d "challenge=$CHALLENGE" \
    -d "uamip=$UAMIP" \
    -d "uamport=$UAMPORT" \
    -d "userurl=$USERURL" \
    -d "myLogin=agb" \
    -d "ll=$LL" \
    -d "nasid=$NASID" \
    -d "custom=$CUSTOM" \
    -d "button=kostenlos+einloggen" \
    "https://www.hotsplots.de/auth/login.php" 2>&1 | tee -a "$LOG_FILE"

echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >/dev/null 2>&1 && exit 0 || exit 1
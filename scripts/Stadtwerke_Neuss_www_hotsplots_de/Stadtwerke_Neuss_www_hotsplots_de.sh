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
REDIRECT_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*[Ll]ocation: \([^ ]*\).*/\1/p' | tr -d '\r' | head -n 1)

if [ -z "$REDIRECT_URL" ]; then
    echo "Primary redirect detection failed, retrying..." | tee -a "$LOG_FILE"
    REDIRECT_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt "http://detectportal.firefox.com/success.txt" 2>&1)
    REDIRECT_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*[Ll]ocation: \([^ ]*\).*/\1/p' | tr -d '\r' | head -n 1)
fi

if [ -z "$REDIRECT_URL" ]; then
    echo "CRITICAL: Could not detect captive portal redirect URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"
QUERY_STRING=$(echo "$REDIRECT_URL" | cut -d'?' -f2)

echo "Fetching login page..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt "$REDIRECT_URL" > /tmp/login_page.html

get_val() {
    grep -i "name="$1"" /tmp/login_page.html | sed -n 's/.*value="\([^"]*\)".*/\1/p' | head -n 1
}

CHALLENGE=$(get_val "challenge")
UAMIP=$(get_val "uamip")
UAMPORT=$(get_val "uamport")
USERURL=$(get_val "userurl")
NASID=$(get_val "nasid")
LL=$(get_val "ll")
CUSTOM=$(get_val "custom")
MYLOGIN=$(get_val "myLogin")

echo "Submitting terms acceptance..." | tee -a "$LOG_FILE"
curl -L -v -A "$USER_AGENT" \
    -b /tmp/cookies.txt -c /tmp/cookies.txt \
    --data-urlencode "haveTerms=1" \
    --data-urlencode "termsOK=on" \
    --data-urlencode "challenge=$CHALLENGE" \
    --data-urlencode "uamip=$UAMIP" \
    --data-urlencode "uamport=$UAMPORT" \
    --data-urlencode "userurl=$USERURL" \
    --data-urlencode "myLogin=$MYLOGIN" \
    --data-urlencode "ll=$LL" \
    --data-urlencode "nasid=$NASID" \
    --data-urlencode "custom=$CUSTOM" \
    --data-urlencode "button=kostenlos einloggen" \
    "https://www.hotsplots.de/auth/login.php?$QUERY_STRING" 2>&1 | tee -a "$LOG_FILE"

echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >/dev/null 2>&1 && exit 0 || exit 1
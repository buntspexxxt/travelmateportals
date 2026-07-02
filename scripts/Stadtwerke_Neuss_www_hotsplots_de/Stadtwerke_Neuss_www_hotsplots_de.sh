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
REDIRECT_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*[Ll]ocation: //p' | tr -d '\r' | head -n 1)

if [ -z "$REDIRECT_URL" ]; then
    echo "No redirect found. Testing connectivity..." | tee -a "$LOG_FILE"
else
    echo "Redirecting to: $REDIRECT_URL" | tee -a "$LOG_FILE"
    echo "Downloading portal HTML..." | tee -a "$LOG_FILE"
    curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt "$REDIRECT_URL" > /tmp/login_page.html

    get_input_value() {
        local name="$1"
        local tag
        tag=$(grep -i "name="$name"" /tmp/login_page.html | head -n 1)
        echo "$tag" | sed -n 's/.*value="\([^"]*\)".*/\1/p'
    }

    get_url_param() {
        local url="$1"
        local param="$2"
        echo "$url" | sed -n "s/.*[?&]$param=\([^&]*\).*/\1/p" | head -n 1
    }

    CHALLENGE=$(get_input_value "challenge")
    UAMIP=$(get_input_value "uamip")
    UAMPORT=$(get_input_value "uamport")
    USERURL=$(get_input_value "userurl")
    MYLOGIN=$(get_input_value "myLogin")
    LL=$(get_input_value "ll")
    NASID=$(get_input_value "nasid")
    CUSTOM=$(get_input_value "custom")

    # Fallback to URL query parameters if HTML parsing is empty
    [ -z "$CHALLENGE" ] && CHALLENGE=$(get_url_param "$REDIRECT_URL" "challenge")
    [ -z "$UAMIP" ] && UAMIP=$(get_url_param "$REDIRECT_URL" "uamip")
    [ -z "$UAMPORT" ] && UAMPORT=$(get_url_param "$REDIRECT_URL" "uamport")
    [ -z "$USERURL" ] && USERURL=$(get_url_param "$REDIRECT_URL" "userurl")
    [ -z "$LL" ] && LL=$(get_url_param "$REDIRECT_URL" "ll")
    [ -z "$NASID" ] && NASID=$(get_url_param "$REDIRECT_URL" "nasid")
    [ -z "$CUSTOM" ] && CUSTOM=$(get_url_param "$REDIRECT_URL" "custom")
    [ -z "$MYLOGIN" ] && MYLOGIN="agb"

    echo "Extracted parameters:" | tee -a "$LOG_FILE"
    echo "CHALLENGE: $CHALLENGE" | tee -a "$LOG_FILE"
    echo "UAMIP: $UAMIP" | tee -a "$LOG_FILE"
    echo "UAMPORT: $UAMPORT" | tee -a "$LOG_FILE"
    echo "USERURL: $USERURL" | tee -a "$LOG_FILE"
    echo "MYLOGIN: $MYLOGIN" | tee -a "$LOG_FILE"
    echo "LL: $LL" | tee -a "$LOG_FILE"
    echo "NASID: $NASID" | tee -a "$LOG_FILE"
    echo "CUSTOM: $CUSTOM" | tee -a "$LOG_FILE"

    POST_DATA="haveTerms=1&termsOK=on&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&userurl=$USERURL&myLogin=$MYLOGIN&ll=$LL&nasid=$NASID&custom=$CUSTOM&button=kostenlos+einloggen"

    echo "Submitting login form to Hotsplots and following redirects..." | tee -a "$LOG_FILE"
    # CRITICAL: -L is added to ensure curl follows the redirect from hotsplots.de back to the local CoovaChilli gateway, completing the MAC authorization flow!
    curl -L -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -d "$POST_DATA" "https://www.hotsplots.de/auth/login.php" 2>&1 | tee -a "$LOG_FILE"
fi

sleep 5
echo "Verifying connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && { echo "Login successful!" | tee -a "$LOG_FILE"; exit 0; } || { echo "Login failed." | tee -a "$LOG_FILE"; exit 1; }
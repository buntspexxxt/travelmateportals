#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting login script for Stadtwerke_Neuss (hotsplots)..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# Clean up old cookies
rm -f /tmp/cookies.txt /tmp/login_page.html

echo "Sending request to trigger captive portal redirect..." | tee -a "$LOG_FILE"
PAGE_CONTENT=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt "http://neverssl.com" 2>&1)

echo "Extracting redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(echo "$PAGE_CONTENT" | grep -i "Location:" | sed -n 's/.*[Ll]ocation: \([^ ]*\).*/\1/p' | tr -d '\r' | tail -n 1)

if [ -z "$REDIRECT_URL" ]; then
    echo "No redirect URL found. Checking if already online..." | tee -a "$LOG_FILE"
    if ping -c 3 8.8.8.8 >/dev/null; then
        echo "Already connected to the internet!" | tee -a "$LOG_FILE"
        exit 0
    else
        echo "Not connected and no redirect found. Exiting." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

echo "Redirect URL found: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Downloading login page HTML..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt "$REDIRECT_URL" > /tmp/login_page.html

echo "Extracting hidden input fields from HTML..." | tee -a "$LOG_FILE"
get_input_value() {
    local name="$1"
    grep -i "name="$name"" /tmp/login_page.html | sed -n 's/.*value="\([^"]*\)".*/\1/p' | head -n 1
}

HAVE_TERMS=$(get_input_value "haveTerms")
CHALLENGE=$(get_input_value "challenge")
UAMIP=$(get_input_value "uamip")
UAMPORT=$(get_input_value "uamport")
USERURL=$(get_input_value "userurl")
MYLOGIN=$(get_input_value "myLogin")
LL=$(get_input_value "ll")
NASID=$(get_input_value "nasid")
CUSTOM=$(get_input_value "custom")

echo "Extracted fields:"
echo "haveTerms: $HAVE_TERMS"
echo "challenge: $CHALLENGE"
echo "uamip: $UAMIP"
echo "uamport: $UAMPORT"
echo "userurl: $USERURL"
echo "myLogin: $MYLOGIN"
echo "ll: $LL"
echo "nasid: $NASID"
echo "custom: $CUSTOM"

# URL encode userurl using standard POSIX sed replacements
USERURL_ENC=$(echo "$USERURL" | sed 's/:/%3A/g; s/\//%2F/g; s/ /+/g; s/&/%26/g; s/?/%3F/g; s/=/%3D/g')

# Build POST body containing accepted terms and dynamically extracted inputs
POST_DATA="haveTerms=${HAVE_TERMS}&termsOK=on&challenge=${CHALLENGE}&uamip=${UAMIP}&uamport=${UAMPORT}&userurl=${USERURL_ENC}&myLogin=${MYLOGIN}&ll=${LL}&nasid=${NASID}&custom=${CUSTOM}&button=kostenlos+einloggen"

echo "Constructed POST data: $POST_DATA" | tee -a "$LOG_FILE"

echo "Extracting form action URL..." | tee -a "$LOG_FILE"
FORM_ACTION=$(grep -i "<form" /tmp/login_page.html | sed -n 's/.*action="\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$FORM_ACTION" ]; then
    FORM_ACTION="https://www.hotsplots.de/auth/login.php"
elif [ "${FORM_ACTION#http}" = "$FORM_ACTION" ]; then
    BASE_URL=$(echo "$REDIRECT_URL" | sed -n 's/\(https*:\/\/[^\/]*\).*/\1/p')
    if [ -z "$BASE_URL" ]; then
        BASE_URL="https://www.hotsplots.de"
    fi
    FORM_ACTION="${BASE_URL}${FORM_ACTION}"
fi

echo "Submitting form to: $FORM_ACTION" | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -d "$POST_DATA" "$FORM_ACTION" 2>&1)

echo "Response received:" | tee -a "$LOG_FILE"
echo "$RESPONSE" | tee -a "$LOG_FILE"

echo "Waiting 5 seconds before checking connectivity..." | tee -a "$LOG_FILE"
sleep 5

echo "Checking internet access..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && { echo "Successfully logged in! Internet is accessible." | tee -a "$LOG_FILE"; exit 0; } || { echo "Login failed or DNS/routing issues. No internet connectivity." | tee -a "$LOG_FILE"; exit 1; }

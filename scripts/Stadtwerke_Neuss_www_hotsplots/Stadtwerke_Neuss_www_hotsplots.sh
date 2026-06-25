#!/usr/bin/env bash
set -e

# Cookie storage
COOKIE_JAR="/tmp/cookies.txt"
HTML_FILE="/tmp/login_page.html"

echo "[1/6] Attempting to reach detectportal.firefox.com to get redirected..."
PORTAL_URL=$(curl -v -L -o /dev/null -w "%{url_effective}" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "http://detectportal.firefox.com/success.txt")

echo "Redirected to portal URL: $PORTAL_URL"

echo "[2/6] Downloading the login page HTML to extract tokens..."
curl -v -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  "$PORTAL_URL" -o "$HTML_FILE"

echo "[3/6] Extracting hidden input values and forms dynamically..."

extract_value() {
    local name="$1"
    grep -o -i -E '<input [^>]*>' "$HTML_FILE" | grep -i "name="$name"" | sed -E 's/.*value="([^"]*)".*/\1/' | head -n 1
}

HAVETERMS=$(extract_value "haveTerms")
CHALLENGE=$(extract_value "challenge")
UAMIP=$(extract_value "uamip")
UAMPORT=$(extract_value "uamport")
USERURL=$(extract_value "userurl")
MYLOGIN=$(extract_value "myLogin")
LL=$(extract_value "ll")
NASID=$(extract_value "nasid")
CUSTOM=$(extract_value "custom")
TERMSOK="on"
BUTTON="kostenlos einloggen"

FORM_ACTION=$(grep -o -i -E '<form [^>]*>' "$HTML_FILE" | grep -i 'action=' | sed -E 's/.*action="([^"]*)".*/\1/' | head -n 1)

echo "Extracted values:"
echo " - haveTerms: $HAVETERMS"
echo " - challenge: $CHALLENGE"
echo " - uamip: $UAMIP"
echo " - uamport: $UAMPORT"
echo " - userurl: $USERURL"
echo " - myLogin: $MYLOGIN"
echo " - ll: $LL"
echo " - nasid: $NASID"
echo " - custom: $CUSTOM"
echo " - form_action: $FORM_ACTION"

if [[ -z "$FORM_ACTION" ]]; then
    echo "Error: Could not extract form action!"
    exit 1
fi

if [[ "$FORM_ACTION" == http* ]]; then
    SUBMIT_URL="$FORM_ACTION"
else
    BASE_URL=$(echo "$PORTAL_URL" | cut -d'/' -f1-3)
    if [[ "$FORM_ACTION" == /* ]]; then
        SUBMIT_URL="${BASE_URL}${FORM_ACTION}"
    else
        SUBMIT_URL="${PORTAL_URL%/*}/${FORM_ACTION}"
    fi
fi

echo "Resolved Submit URL: $SUBMIT_URL"

echo "[4/6] Submitting the login form with AGB accepted..."
RESPONSE=$(curl -v -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  --data-urlencode "haveTerms=${HAVETERMS:-1}" \
  --data-urlencode "termsOK=${TERMSOK}" \
  --data-urlencode "challenge=${CHALLENGE}" \
  --data-urlencode "uamip=${UAMIP}" \
  --data-urlencode "uamport=${UAMPORT}" \
  --data-urlencode "userurl=${USERURL}" \
  --data-urlencode "myLogin=${MYLOGIN:-agb}" \
  --data-urlencode "ll=${LL:-de}" \
  --data-urlencode "nasid=${NASID}" \
  --data-urlencode "custom=${CUSTOM:-1}" \
  --data-urlencode "button=${BUTTON}" \
  "$SUBMIT_URL")

echo "HTTP Response from login submit:"
echo "$RESPONSE"

echo "[5/6] Waiting for network configuration to apply..."
sleep 5

echo "[6/6] Verifying internet connectivity..."
if ping -c 3 8.8.8.8 >/dev/null; then
    echo "SUCCESS: Internet is connected!"
    exit 0
else
    echo "FAILURE: Internet connection could not be established."
    exit 1
fi
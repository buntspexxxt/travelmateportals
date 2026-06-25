#!/bin/bash

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/hotsplots_cookies.txt"

echo "Starting Hotsplots login process..."

# 1. Fetch the portal page to get initial cookies and form fields
echo "Fetching portal page to extract hidden fields..."
RESPONSE_HTML=$(curl -v -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" "https://www.hotsplots.de/auth/login.php" 2>&1)

# 2. Extract hidden form fields dynamically
EXTRACT_VAL() {
  echo "$RESPONSE_HTML" | grep -o "name="$1" value="[^"]*"" | cut -d'"' -f4
}

CHALLENGE=$(EXTRACT_VAL "challenge")
UAMIP=$(EXTRACT_VAL "uamip")
UAMPORT=$(EXTRACT_VAL "uamport")
USERURL=$(EXTRACT_VAL "userurl")
NASID=$(EXTRACT_VAL "nasid")
MYLOGIN="agb"
LL="en"
CUSTOM="1"

if [ -z "$CHALLENGE" ]; then
  echo "Error: Could not extract hidden fields. Portal structure might have changed."
  exit 1
fi

echo "Extracted Challenge: $CHALLENGE"

# 3. Submit the login form
echo "Submitting acceptance form..."
POST_DATA="challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&userurl=$USERURL&myLogin=$MYLOGIN&ll=$LL&nasid=$NASID&custom=$CUSTOM&hotsplots-colibri-terms=on"

LOGIN_RESPONSE=$(curl -v -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -X POST -d "$POST_DATA" "https://www.hotsplots.de/auth/login.php" 2>&1)

echo "Login submission complete."

# 4. Connectivity check
echo "Checking connectivity..."
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" http://neverssl.com)
echo "Connectivity check HTTP status: $HTTP_STATUS"

if [ "$HTTP_STATUS" == "200" ]; then
  echo "Successfully logged in!"
  exit 0
else
  echo "Login failed or still redirected."
  exit 1
fi
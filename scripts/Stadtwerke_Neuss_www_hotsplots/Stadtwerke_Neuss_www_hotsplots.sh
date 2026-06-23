#!/bin/bash

# This script automates the login process for the Hotspots.de captive portal for 'Stadtwerke_Neuss_www_hotsplots'.
# It navigates the initial redirect, extracts dynamic parameters from the login page HTML,
# accepts the terms and conditions, and performs the login.

# --- Configuration and Variables ---

# Initial URL to check for internet connectivity, which triggers the captive portal redirect.
# This URL is used to capture the initial redirect to the portal.
INITIAL_CHECK_URL="http://detectportal.firefox.com/"

# Temporary file to store cookies for the session.
COOKIE_JAR="/tmp/hotsplots_cookies.txt"

# Temporary file to store the downloaded HTML of the login page.
HTML_OUTPUT="/tmp/hotsplots_login_page.html"

# Ensure temporary files are cleaned up on exit
trap "rm -f \"$COOKIE_JAR\" \"$HTML_OUTPUT\"" EXIT

# --- Step 1: Initiate Connectivity Check and Capture Login Page HTML ---

echo "$(date): --- Starting Hotspots.de Login Script for SSID Stadtwerke_Neuss_www_hotsplots ---"
echo "$(date): Step 1: Initiating connectivity check to '$INITIAL_CHECK_URL' to capture the captive portal redirect URL and login page HTML."

# Perform a curl request to the initial check URL.
# -v: verbose output to stderr, useful for debugging.
# -L: follow redirects.
# -o "$HTML_OUTPUT": save the final page content (after redirects) to a file.
# -c "$COOKIE_JAR": save cookies to the cookie jar file.
# 2>&1: redirect stderr (where verbose output goes) to stdout so we can capture it.
# tee /dev/stderr: print verbose output to stderr while also passing it to a variable

RESPONSE_HEADERS=$(curl -v -L -o "$HTML_OUTPUT" -c "$COOKIE_JAR" "$INITIAL_CHECK_URL" 2>&1)

# Extract the HTTP status code from the last response in the verbose output.
HTTP_STATUS=$(echo "$RESPONSE_HEADERS" | grep -i "< HTTP/" | tail -1 | awk '{print $3}' | tr -d '\r')
echo "$(date): HTTP Status after initial check and following redirects: $HTTP_STATUS"

# Check if the initial request failed to get a 200 OK after redirects.
if [ "$HTTP_STATUS" != "200" ]; then
    echo "$(date): ERROR: Initial request did not result in HTTP 200 OK. Received $HTTP_STATUS."
    echo "$(date): Full verbose response for debugging:"
    echo "$RESPONSE_HEADERS"
    exit 1
fi

# The final URL after all redirects is typically the login page itself.
# We can extract it from the verbose output by looking for the last effective URL.
LANDING_URL=$(echo "$RESPONSE_HEADERS" | grep -E '^\* Max-Age|^< Location:|^\*  URL transformed to ' | tail -1 | awk '{print $NF}' | tr -d '\r')
# If LANDING_URL is empty, try to get it from the last effective URL which is usually the last line of verbose output.
if [ -z "$LANDING_URL" ]; then
    LANDING_URL=$(echo "$RESPONSE_HEADERS" | grep -E '\*.*connected to|^>.*Host:|^>.*GET|^<.*Location:|^<.*Content-Location:' | tail -1 | awk '{print $NF}' | tr -d '\r')
fi

echo "$(date): Captured landing page URL (after redirects): $LANDING_URL"

# Check if the HTML file was actually downloaded and is not empty.
if [ ! -s "$HTML_OUTPUT" ]; then
    echo "$(date): ERROR: The HTML login page was not downloaded or is empty. Cannot proceed."
    echo "$(date): Full verbose response for debugging:"
    echo "$RESPONSE_HEADERS"
    exit 1
fi

# --- Step 2: Extract Form Action URL and Hidden Inputs from HTML ---

echo "$(date): Step 2: Parsing the downloaded HTML ('$HTML_OUTPUT') to extract form details."

# Extract the form's action URL.
LOGIN_FORM_ACTION=$(grep -oP '<form method="post" action="\K[^\"]+' "$HTML_OUTPUT" | head -1)
if [ -z "$LOGIN_FORM_ACTION" ]; then
    echo "$(date): ERROR: Could not find the login form action URL in the HTML."
    exit 1
fi
echo "$(date): Extracted login form action URL: $LOGIN_FORM_ACTION"

# Extract all hidden input fields dynamically. This is crucial as values can change.
# haveTerms is a static value '1' but extracted for robustness.
# termsOK is the checkbox, which needs to be sent as 'on'.
haveTerms=$(grep -oP 'name="haveTerms" value="\K[^\"]+' "$HTML_OUTPUT" | head -1)
challenge=$(grep -oP 'name="challenge" value="\K[^\"]+' "$HTML_OUTPUT" | head -1)
uamip=$(grep -oP 'name="uamip" value="\K[^\"]+' "$HTML_OUTPUT" | head -1)
uamport=$(grep -oP 'name="uamport" value="\K[^\"]+' "$HTML_OUTPUT" | head -1)
userurl=$(grep -oP 'name="userurl" value="\K[^\"]+' "$HTML_OUTPUT" | head -1)
myLogin=$(grep -oP 'name="myLogin" value="\K[^\"]+' "$HTML_OUTPUT" | head -1)
ll=$(grep -oP 'name="ll" value="\K[^\"]+' "$HTML_OUTPUT" | head -1)
nasid=$(grep -oP 'name="nasid" value="\K[^\"]+' "$HTML_OUTPUT" | head -1)
custom=$(grep -oP 'name="custom" value="\K[^\"]+' "$HTML_OUTPUT" | head -1)

# Check if critical parameters were extracted.
if [ -z "$challenge" ] || [ -z "$uamip" ] || [ -z "$uamport" ] || [ -z "$userurl" ]; then
    echo "$(date): ERROR: One or more critical hidden parameters (challenge, uamip, uamport, userurl) could not be extracted."
    exit 1
fi

echo "$(date): Extracted hidden fields:"
echo "$(date):   haveTerms='$haveTerms'"
echo "$(date):   challenge='$challenge'"
echo "$(date):   uamip='$uamip'"
echo "$(date):   uamport='$uamport'"
echo "$(date):   userurl='$userurl'"
echo "$(date):   myLogin='$myLogin'"
echo "$(date):   ll='$ll'"
echo "$(date):   nasid='$nasid'"
echo "$(date):   custom='$custom'"

# --- Step 3: Construct POST Data ---

echo "$(date): Step 3: Constructing POST data for the login request."

# The portal requires 'termsOK=on' for the checkbox and 'button=kostenlos einloggen' for the submit button.
# curl will automatically URL-encode these values when using -d.
POST_DATA="haveTerms=${haveTerms}&termsOK=on&button=kostenlos+einloggen&challenge=${challenge}&uamip=${uamip}&uamport=${uamport}&userurl=${userurl}&myLogin=${myLogin}&ll=${ll}&nasid=${nasid}&custom=${custom}"

echo "$(date): POST Data to be sent: $POST_DATA"

# --- Step 4: Submit Login Request ---

echo "$(date): Step 4: Submitting the login request to '$LOGIN_FORM_ACTION'."

# Perform the POST request.
# -X POST: explicitly set request method to POST.
# -d "$POST_DATA": send the constructed POST data.
# -b "$COOKIE_JAR": send cookies from the cookie jar.
# -c "$COOKIE_JAR": save any new cookies to the cookie jar.
# -L: follow redirects after login.
LOGIN_RESPONSE=$(curl -v -L -X POST -d "$POST_DATA" -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$LOGIN_FORM_ACTION" 2>&1)

LOGIN_HTTP_STATUS=$(echo "$LOGIN_RESPONSE" | grep -i "< HTTP/" | tail -1 | awk '{print $3}' | tr -d '\r')
echo "$(date): HTTP Status after login attempt: $LOGIN_HTTP_STATUS"

# Print the full login response for debugging.
echo "$(date): Full login response (verbose) for debugging:"
echo "$LOGIN_RESPONSE"

# Check if the login attempt was successful. A 200 OK or a redirect (3xx) to the original userurl
# or a success page indicates success.
if [[ "$LOGIN_HTTP_STATUS" == "200" || "$LOGIN_HTTP_STATUS" =~ ^3[0-9]{2}$ ]]; then
    echo "$(date): Login request sent successfully. Server responded with HTTP $LOGIN_HTTP_STATUS."
else
    echo "$(date): ERROR: Login request failed. Received HTTP $LOGIN_HTTP_STATUS."
    exit 1
fi

# --- Step 5: Verify Internet Connectivity ---

echo "$(date): Step 5: Verifying internet connectivity by pinging 8.8.8.8 (Google DNS)."

ping -c 3 8.8.8.8 > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "$(date): SUCCESS: Internet connectivity confirmed."
    exit 0
else
    echo "$(date): ERROR: Internet connectivity not established after login attempt."
    exit 1
fi


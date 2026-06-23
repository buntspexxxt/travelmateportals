#!/bin/bash

# CRITICAL: This script assumes it is run in an environment where network access
# is restricted by the captive portal.
# CRITICAL: DO NOT run this script if you are already connected to the internet via this network,
# as it might cause unexpected behavior or log you out.

# --- Configuration --- START ---
COOKIE_FILE="/tmp/hotsplots_cookies.txt"
# --- Configuration --- END ---


# --- Step 1: Initialize logging and cleanup --- 

echo "INFO: Starting captive portal login script for WIFI_DB_auth_hotsplots."
rm -f "$COOKIE_FILE"


# --- Step 2: Detect the initial redirect URL from detectportal.firefox.com ---

echo "INFO: Sending initial HEAD request to detectportal.firefox.com to find the captive portal redirect."

# Use -s (silent), -L (follow redirects), -D (dump headers to stderr) to get the final URL
LANDING_PAGE_HEADERS=$(curl -s -L -D /dev/stderr -o /dev/null http://detectportal.firefox.com/)

# Extract the final effective URL from the headers
LANDING_URL=$(echo "$LANDING_PAGE_HEADERS" | grep -i '^Location:' | tail -1 | awk '{print $2}' | tr -d '\r\n')

if [ -z "$LANDING_URL" ]; then
    echo "ERROR: Could not determine the landing URL from detectportal.firefox.com. Exiting."
    echo "DEBUG: Headers received:"
    echo "$LANDING_PAGE_HEADERS"
    exit 1
fi

# Extract the base URL (domain + path) without query parameters for cleaner processing if needed
# However, the hotsplots portal needs the full URL including query params for the GET and POST requests.
# So, LANDING_URL will be used as is.

echo "INFO: Initial captive portal landing URL detected: $LANDING_URL"


# --- Step 3: Fetch the login page HTML to extract hidden form fields and establish session cookies ---

echo "INFO: Fetching the login page HTML from $LANDING_URL to extract form data."

# Use -v for verbose output, -L to follow redirects, -c to save cookies, -b to send cookies
HTML_RESPONSE=$(curl -v -L -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LANDING_URL" 2>&1)
CURL_STATUS=$?

if [ $CURL_STATUS -ne 0 ]; then
    echo "ERROR: Failed to fetch the login page from $LANDING_URL. Curl exited with status $CURL_STATUS."
    echo "DEBUG: Curl output:"
    echo "$HTML_RESPONSE"
    exit 1
fi

# Extract HTTP response code
HTTP_CODE=$(echo "$HTML_RESPONSE" | grep '< HTTP/' | awk '{print $2}' | tail -1)
echo "INFO: Received HTTP $HTTP_CODE for GET request to $LANDING_URL."

# Extract the HTML body from the verbose curl output
HTML_BODY=$(echo "$HTML_RESPONSE" | sed -n '/^< HTML/,/^* Connection/p' | sed '$ d')

# CRITICAL: Dynamically extract all hidden input fields and the CSRF token
CHALLENGE=$(echo "$HTML_BODY" | grep -oP 'name="login_status_form\[challenge\]" value="\K[^"]*')
UAMIP=$(echo "$HTML_BODY" | grep -oP 'name="login_status_form\[uamip\]" value="\K[^"]*')
UAMPORT=$(echo "$HTML_BODY" | grep -oP 'name="login_status_form\[uamport\]" value="\K[^"]*')
LL=$(echo "$HTML_BODY" | grep -oP 'name="login_status_form\[ll\]" value="\K[^"]*')
MYLOGIN=$(echo "$HTML_BODY" | grep -oP 'name="login_status_form\[myLogin\]" value="\K[^"]*')
TOKEN=$(echo "$HTML_BODY" | grep -oP 'name="login_status_form\[_token\]" value="\K[^"]*')

if [ -z "$CHALLENGE" ] || [ -z "$UAMIP" ] || [ -z "$UAMPORT" ] || [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to extract one or more required hidden form fields (challenge, uamip, uamport, _token). Exiting."
    echo "DEBUG: Challenge: '$CHALLENGE', UAMIP: '$UAMIP', UAMPORT: '$UAMPORT', LL: '$LL', MYLOGIN: '$MYLOGIN', Token: '$TOKEN'"
    echo "DEBUG: HTML Body excerpt: $(echo "$HTML_BODY" | head -n 20)"
    exit 1
fi

echo "INFO: Successfully extracted hidden form fields:"
echo "INFO:   challenge = '$CHALLENGE'"
echo "INFO:   uamip = '$UAMIP'"
echo "INFO:   uamport = '$UAMPORT'"
echo "INFO:   ll = '$LL' (might be empty)"
echo "INFO:   myLogin = '$MYLOGIN' (might be empty)"
echo "INFO:   _token = '$TOKEN'"


# --- Step 4: Construct POST data and submit the form ---

# URL-encode the values to be safe, especially for the token
POST_DATA="login_status_form[challenge]=$(echo "$CHALLENGE" | sed 's/[&]/%26/g;s/[=]/%3D/g')&"
POST_DATA+="login_status_form[uamip]=$(echo "$UAMIP" | sed 's/[&]/%26/g;s/[=]/%3D/g')&"
POST_DATA+="login_status_form[uamport]=$(echo "$UAMPORT" | sed 's/[&]/%26/g;s/[=]/%3D/g')&"
POST_DATA+="login_status_form[ll]=$(echo "$LL" | sed 's/[&]/%26/g;s/[=]/%3D/g')&"
POST_DATA+="login_status_form[myLogin]=$(echo "$MYLOGIN" | sed 's/[&]/%26/g;s/[=]/%3D/g')&"
POST_DATA+="login_status_form[_token]=$(echo "$TOKEN" | sed 's/[&]/%26/g;s/[=]/%3D/g')&"
POST_DATA+="login_status_form[button]="

echo "INFO: Submitting login form to $LANDING_URL."
echo "DEBUG: POST data: $POST_DATA"

LOGIN_RESPONSE=$(curl -v -L -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST -d "$POST_DATA" "$LANDING_URL" 2>&1)
CURL_STATUS=$?

if [ $CURL_STATUS -ne 0 ]; then
    echo "ERROR: Failed to submit the login form. Curl exited with status $CURL_STATUS."
    echo "DEBUG: Curl output:"
    echo "$LOGIN_RESPONSE"
    exit 1
fi

# Extract HTTP response code after POST
HTTP_CODE=$(echo "$LOGIN_RESPONSE" | grep '< HTTP/' | awk '{print $2}' | tail -1)
echo "INFO: Received HTTP $HTTP_CODE after POST request to $LANDING_URL."

if [[ "$LOGIN_RESPONSE" =~ "Successfully logged in" || "$LOGIN_RESPONSE" =~ "You are now online" || "$HTTP_CODE" =~ ^2 ]]; then
    echo "INFO: Login attempt completed. Checking internet connectivity..."
else
    echo "WARNING: Login POST did not return an obvious success message or a 2xx HTTP status. It might have redirected or failed silently. Proceeding to connectivity check."
    echo "DEBUG: Final response (last 20 lines):\n$(echo "$LOGIN_RESPONSE" | tail -n 20)"
fi


# --- Step 5: Verify internet connectivity ---

echo "INFO: Pinging 8.8.8.8 to verify internet connectivity (3 attempts)."
ping -c 3 8.8.8.8 > /dev/null

if [ $? -eq 0 ]; then
    echo "INFO: Successfully connected to the internet. Portal login successful!"
    exit 0
else
    echo "ERROR: Failed to connect to the internet after portal login attempt. Portal login might have failed."
    exit 1
fi

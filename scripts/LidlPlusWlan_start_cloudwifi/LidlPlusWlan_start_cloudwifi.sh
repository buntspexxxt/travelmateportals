#!/bin/bash

# This script automates the login process for the 'LidlPlusWlan_start_cloudwifi' captive portal.
# It identifies the initial redirect, extracts dynamic parameters, retrieves hidden form fields,
# submits an "Easy Login" form, and verifies internet connectivity.

# --- Configuration Variables ---
TEMP_DIR="/tmp/lidl_wlan_portal_$(date +%s)" # Temporary directory for storing files
COOKIE_JAR="$TEMP_DIR/cookies.txt"       # File to store and read HTTP cookies
LOGIN_PAGE_HTML="$TEMP_DIR/login_page.html" # File to store the downloaded login page HTML
TEST_URL="http://detectportal.firefox.com/" # A known URL to trigger captive portal redirect
SUCCESS_PING_IP="8.8.8.8"               # IP address to ping for connectivity check

# --- Script Start ---

echo "--- Starting Captive Portal Login Script ---"

# 1. Prepare environment: Create a temporary directory
echo "INFO: Creating temporary directory '$TEMP_DIR' for session files..."
mkdir -p "$TEMP_DIR"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create temporary directory '$TEMP_DIR'. Exiting." >&2
    exit 1
fi
echo "INFO: Temporary directory created successfully at '$TEMP_DIR'."

# 2. Initial request to trigger captive portal and capture the redirect URL
echo "INFO: Step 1/5: Making initial request to '$TEST_URL' to trigger captive portal redirect."
echo "INFO: Capturing effective URL and cookies for subsequent requests."
INITIAL_CURL_OUTPUT=$(curl -L -v -c "$COOKIE_JAR" -o /dev/null "$TEST_URL" 2>&1)
INITIAL_HTTP_CODE=$(echo "$INITIAL_CURL_OUTPUT" | grep -oP '^< HTTP/\d\.\d \K\d+' | tail -n 1)

echo "DEBUG: Full curl output for initial request:"
echo "$INITIAL_CURL_OUTPUT"
echo "DEBUG: Final HTTP status code from initial request: $INITIAL_HTTP_CODE"

EFFECTIVE_URL=$(echo "$INITIAL_CURL_OUTPUT" | grep -oP '(?<=^< Location: |^> GET )[^\s\r\n]+(?= HTTP/\d\.\d$|$)' | tail -n 1)

if [ -z "$EFFECTIVE_URL" ]; then
    echo "ERROR: Could not determine effective URL after initial redirect. Captive portal not found or unexpected redirect. Exiting." >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "INFO: Effective URL of the captive portal landing page: $EFFECTIVE_URL"

# 3. Download the login page to extract hidden form fields
echo "INFO: Step 2/5: Downloading the login page HTML from '$EFFECTIVE_URL'."
echo "INFO: This is necessary to dynamically extract hidden form fields for login."
DOWNLOAD_HTML_OUTPUT=$(curl -L -v -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$EFFECTIVE_URL" -o "$LOGIN_PAGE_HTML" 2>&1)
DOWNLOAD_HTTP_CODE=$(echo "$DOWNLOAD_HTML_OUTPUT" | grep -oP '^< HTTP/\d\.\d \K\d+' | tail -n 1)

echo "DEBUG: Full curl output for downloading login page:"
echo "$DOWNLOAD_HTML_OUTPUT"
echo "DEBUG: Final HTTP status code from download request: $DOWNLOAD_HTTP_CODE"

if [ ! -f "$LOGIN_PAGE_HTML" ] || [ ! -s "$LOGIN_PAGE_HTML" ]; then
    echo "ERROR: Failed to download login page HTML or the file '$LOGIN_PAGE_HTML' is empty. Exiting." >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "INFO: Login page HTML downloaded successfully to '$LOGIN_PAGE_HTML'."

# 4. Extract hidden form fields for the "Easy Login" form (FX_loginform_0)
echo "INFO: Step 3/5: Extracting hidden form fields from 'FX_loginform_0' in the downloaded HTML."
POST_DATA_FIELDS=(
    "cbQpC" "nasid" "mac" "challenge" "uamip" "uamport" "called"
    "userurl" "sessionid" "FX_username" "FX_password" "FX_loginTemplate"
    "FX_loginType" "FX_remoteAddr" "FX_hotspotDeviceId" "FX_lang"
)

POST_DATA=""

# Function to extract a hidden input field value by name
extract_hidden_field() {
    local FIELD_NAME="$1"
    # Use grep to find the input tag, then sed to extract the value attribute
    local FIELD_VALUE=$(grep -oP "<input type=\"hidden\" name=\"$FIELD_NAME\" value=\"\K[^\" rel=nofollow ]+" "$LOGIN_PAGE_HTML" | head -n 1)
    # Decode HTML entities like &#x3D; to =
    FIELD_VALUE=$(echo "$FIELD_VALUE" | sed 's/&#x3D;/=/g; s/&amp;/&/g')

    echo "DEBUG: Extracted field '$FIELD_NAME': '$FIELD_VALUE'"

    # Append to POST_DATA, URL-encoding the value
    if [ -n "$FIELD_VALUE" ]; then
        if [ -z "$POST_DATA" ]; then
            POST_DATA="${FIELD_NAME}=$(printf "%s" "$FIELD_VALUE" | xxd -plain | sed 's/\(..\)/%\1/g')"
        else
            POST_DATA="${POST_DATA}&${FIELD_NAME}=$(printf "%s" "$FIELD_VALUE" | xxd -plain | sed 's/\(..\)/%\1/g')"
        fi
    else
        echo "WARNING: Could not find or extract value for hidden field: $FIELD_NAME. Appending an empty value." >&2
        if [ -z "$POST_DATA" ]; then
            POST_DATA="${FIELD_NAME}="
        else
            POST_DATA="${POST_DATA}&${FIELD_NAME}="
        fi
    fi
}

# Loop through the list of fields and extract their values
for field in "${POST_DATA_FIELDS[@]}"; do
    extract_hidden_field "$field"
done

if [ -z "$POST_DATA" ]; then
    echo "ERROR: No POST data could be extracted from the login form. Exiting." >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "INFO: Successfully constructed POST data: '$POST_DATA'"

# 5. Submit the login form (Easy Login)
echo "INFO: Step 4/5: Submitting the login form using the extracted POST data to '$EFFECTIVE_URL'."
echo "INFO: Using previously captured cookies for the request."
LOGIN_RESPONSE=$(curl -L -v -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X POST -d "$POST_DATA" "$EFFECTIVE_URL" 2>&1)
LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE" | grep -oP '^< HTTP/\d\.\d \K\d+' | tail -n 1)

echo "DEBUG: Full curl output for login POST request:"
echo "$LOGIN_RESPONSE"
echo "DEBUG: Final HTTP status code from login POST request: $LOGIN_HTTP_CODE"

# Check if the login was successful (e.g., redirect to success page, 200 OK)
if [ "$LOGIN_HTTP_CODE" -ge 200 ] && [ "$LOGIN_HTTP_CODE" -lt 400 ]; then
    echo "INFO: Login request likely successful (HTTP status $LOGIN_HTTP_CODE)."
else
    echo "ERROR: Login request failed or returned an unexpected HTTP status code: $LOGIN_HTTP_CODE. Exiting." >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 6. Verify internet connectivity
echo "INFO: Step 5/5: Verifying internet connectivity by pinging '$SUCCESS_PING_IP'."
if ping -c 3 "$SUCCESS_PING_IP" > /dev/null; then
    echo "SUCCESS: Internet connectivity confirmed after successful login!"
    echo "INFO: Cleaning up temporary directory '$TEMP_DIR'."
    rm -rf "$TEMP_DIR"
    exit 0
else
    echo "ERROR: Failed to establish internet connectivity after login attempt." >&2
    echo "INFO: Cleaning up temporary directory '$TEMP_DIR'."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# --- Script End ---

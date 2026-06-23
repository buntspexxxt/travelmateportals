#!/bin/bash

# Critical: Enable verbose logging for debugging
set -x

# Temporary files for cookies and HTML content
COOKIE_JAR=$(mktemp)
HTML_PAGE=$(mktemp)

echo "Starting captive portal login script for WIFI_DB_auth_hotsplots..."
echo "Temporary cookie jar: $COOKIE_JAR"
echo "Temporary HTML page: $HTML_PAGE"

cleanup() {
    echo "Cleaning up temporary files..."
    rm -f "$COOKIE_JAR" "$HTML_PAGE"
    echo "Cleanup complete."
}
trap cleanup EXIT

# 1. Initial Request to trigger redirect and capture landing URL
echo "Step 1: Attempting to reach http://detectportal.firefox.com/ to trigger captive portal redirect."
INITIAL_URL="http://detectportal.firefox.com/"

# Capture effective URL and verbose output
CURL_OUTPUT=$(curl -vv -L -o /dev/null -w "%{url_effective}" "$INITIAL_URL" 2>&1)
CURL_STATUS=$?
LANDING_URL=$(echo "$CURL_OUTPUT" | tail -n 1)

if [ "$CURL_STATUS" -ne 0 ] || [ -z "$LANDING_URL" ]; then
    echo "ERROR: curl failed to get effective URL after initial redirect. Status: $CURL_STATUS."
    echo "Curl Output: $CURL_OUTPUT"
    exit 1
fi

echo "Effective landing URL captured: $LANDING_URL"

# Extract base domain from LANDING_URL (e.g., auth.hotsplots.de)
BASE_DOMAIN=$(echo "$LANDING_URL" | sed -E 's/https?:\/\/(www\.)?([^/?#]+).*/\2/')
echo "Base domain extracted: $BASE_DOMAIN"

# 2. Fetch the actual portal login page and save cookies
echo "Step 2: Fetching the login page from $LANDING_URL to extract form fields and initial cookies."
# Capture response code and HTML content
HTTP_RESPONSE_CODE=$(curl -vv -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$LANDING_URL" -o "$HTML_PAGE" -w "%{http_code}" 2>&1)
CURL_STATUS=$?

if [ "$CURL_STATUS" -ne 0 ] || [ "$HTTP_RESPONSE_CODE" -ge 400 ]; then
    echo "ERROR: curl failed to fetch the login page with status $CURL_STATUS. HTTP Code: $HTTP_RESPONSE_CODE."
    echo "Curl Output: $HTTP_RESPONSE_CODE"
    cat "$HTML_PAGE" # Print fetched content for debug
    exit 1
fi
echo "Login page fetched successfully. HTTP Response Code: $(echo "$HTTP_RESPONSE_CODE" | tail -n 1)"
echo "HTML content saved to $HTML_PAGE."

# Read HTML content for parsing
HTML_CONTENT=$(cat "$HTML_PAGE")

# 3. Extract hidden form fields dynamically
echo "Step 3: Extracting hidden form fields from the HTML."

# Define a function to extract hidden input values
extract_hidden_field() {
    local field_name="$1"
    local html_content="$2"
    # Use grep -oP for PCRE regex and extract the value group
    echo "$html_content" | grep -oP "name=\"login_status_form\[${field_name}\]\" value=\"\K[^"]*" | head -1
}

CHALLENGE=$(extract_hidden_field "challenge" "$HTML_CONTENT")
UAMIP=$(extract_hidden_field "uamip" "$HTML_CONTENT")
UAMPORT=$(extract_hidden_field "uamport" "$HTML_CONTENT")
LL_FIELD=$(extract_hidden_field "ll" "$HTML_CONTENT")
MYLOGIN_FIELD=$(extract_hidden_field "myLogin" "$HTML_CONTENT")
CSRF_TOKEN=$(extract_hidden_field "_token" "$HTML_CONTENT")

if [ -z "$CHALLENGE" ]; then echo "ERROR: Could not extract challenge field."; exit 1; fi
if [ -z "$UAMIP" ]; then echo "ERROR: Could not extract uamip field."; exit 1; fi
if [ -z "$UAMPORT" ]; then echo "ERROR: Could not extract uamport field."; exit 1; fi
# ll and myLogin can be empty, no error check needed for them
if [ -z "$CSRF_TOKEN" ]; then echo "ERROR: Could not extract CSRF token (_token) field. This is critical."; exit 1; fi

echo "Extracted Challenge: $CHALLENGE"
echo "Extracted UAMIP: $UAMIP"
echo "Extracted UAMPORT: $UAMPORT"
echo "Extracted LL (can be empty): '${LL_FIELD}'"
echo "Extracted MyLogin (can be empty): '${MYLOGIN_FIELD}'"
echo "Extracted CSRF Token: $CSRF_TOKEN"

# 4. Construct POST data
echo "Step 4: Constructing POST data for login."
# URL-encode the values in case they contain special characters
POST_DATA="login_status_form[button]=&login_status_form[challenge]=$(echo -n "$CHALLENGE" | xxd -plain | sed 's/\(..\)/%\1/g')&login_status_form[uamip]=$(echo -n "$UAMIP" | xxd -plain | sed 's/\(..\)/%\1/g')&login_status_form[uamport]=$(echo -n "$UAMPORT" | xxd -plain | sed 's/\(..\)/%\1/g')&login_status_form[ll]=$(echo -n "$LL_FIELD" | xxd -plain | sed 's/\(..\)/%\1/g')&login_status_form[myLogin]=$(echo -n "$MYLOGIN_FIELD" | xxd -plain | sed 's/\(..\)/%\1/g')&login_status_form[_token]=$(echo -n "$CSRF_TOKEN" | xxd -plain | sed 's/\(..\)/%\1/g')"
echo "POST Data: $POST_DATA"

# 5. Submit the login form
echo "Step 5: Submitting the login form to $LANDING_URL with cookies."
# Capture response code and verbose output
LOGIN_RESPONSE_OUTPUT=$(curl -vv -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST -d "$POST_DATA" "$LANDING_URL" -o /dev/null -w "%{http_code}" 2>&1)
CURL_STATUS=$?
LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE_OUTPUT" | tail -n 1)

if [ "$CURL_STATUS" -ne 0 ] || [ "$LOGIN_HTTP_CODE" -ge 400 ]; then
    echo "ERROR: curl failed to submit the login form with status $CURL_STATUS. HTTP Code: $LOGIN_HTTP_CODE."
    echo "Curl Output: $LOGIN_RESPONSE_OUTPUT"
    exit 1
fi
echo "Login form submitted successfully. HTTP Response Code: $LOGIN_HTTP_CODE"

# 6. Connectivity Check
echo "Step 6: Performing connectivity check by pinging 8.8.8.8."
ping -c 3 8.8.8.8 > /dev/null
PING_STATUS=$?

if [ "$PING_STATUS" -eq 0 ]; then
    echo "Connectivity check successful. Internet access confirmed."
    exit 0
else
    echo "Connectivity check failed. Internet access not confirmed."
    exit 1
fi

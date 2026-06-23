#!/bin/bash
# Captive portal login script for WIFI_DB_auth_hotsplots

# --- Configuration ---
COOKIE_FILE="/tmp/hotsplots_cookies.txt"
HTML_FILE="/tmp/hotsplots_login_page.html"
PORTAL_DETECT_URL="http://detectportal.firefox.com/"
CURL_OPTIONS="-s -L --max-time 30" # Silent, follow redirects, 30s timeout

echo "--- Captive Portal Login Script for WIFI_DB_auth_hotsplots ---"
echo "Starting analysis and login process."

# Clean up previous session files
rm -f "$COOKIE_FILE" "$HTML_FILE"

# Function to extract a hidden field value from HTML
extract_hidden_field() {
    local field_name_pattern="$1"
    local html_file="$2"
    # Escape brackets for grep -P (Perl-compatible regex)
    local escaped_field_name=$(echo "$field_name_pattern" | sed 's/\[/\[/g; s/\]/\]/g')
    # Use grep -oP with \K to extract only the value part efficiently
    local value=$(grep -oP "<input type=\"hidden\"[^>]*name=\"$escaped_field_name\"[^>]*value=\"\\K[^"\\]*" "$html_file" | head -1)
    echo "$value"
}

# 1. Initial request to trigger portal redirect and capture landing URL
echo "Step 1: Initiating portal detection and capturing landing URL..."
echo "Requesting: $PORTAL_DETECT_URL"
# Use -v to get verbose output including headers for debugging, -o /dev/null to discard body
# -w '%{url_effective}\n' prints the final effective URL after all redirects
INITIAL_CURL_OUTPUT=$(curl $CURL_OPTIONS -v -o /dev/null -D /dev/stderr -w '%{url_effective}\n' "$PORTAL_DETECT_URL" -c "$COOKIE_FILE" 2>&1)
HTTP_STATUS=$(echo "$INITIAL_CURL_OUTPUT" | grep -oP '^< HTTP/\d\.\d \K\d{3}' | tail -1)
LANDING_URL=$(echo "$INITIAL_CURL_OUTPUT" | tail -1)

echo "HTTP Status (last redirect): $HTTP_STATUS"
echo "Landing URL: $LANDING_URL"

if [ -z "$LANDING_URL" ]; then
    echo "ERROR: Failed to capture landing URL. Exiting."
    echo "Curl output for initial request: $INITIAL_CURL_OUTPUT"
    exit 1
fi

# 2. Fetch the login page HTML
echo "Step 2: Fetching the login page HTML from $LANDING_URL..."
echo "Saving HTML to: $HTML_FILE"
HTML_CURL_OUTPUT=$(curl $CURL_OPTIONS -v -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o "$HTML_FILE" "$LANDING_URL" 2>&1)
HTML_STATUS=$(echo "$HTML_CURL_OUTPUT" | grep -oP '^< HTTP/\d\.\d \K\d{3}' | tail -1)
echo "HTTP Status for HTML fetch: $HTML_STATUS"

if [ ! -s "$HTML_FILE" ]; then
    echo "ERROR: Failed to download HTML content or file is empty. Exiting."
    echo "Curl output for HTML fetch: $HTML_CURL_OUTPUT"
    exit 1
fi
echo "HTML content successfully saved to $HTML_FILE"

# 3. Extract hidden form fields
echo "Step 3: Extracting hidden form fields required for login from $HTML_FILE..."

CHALLENGE=$(extract_hidden_field "login_status_form[challenge]" "$HTML_FILE")
UAMIP=$(extract_hidden_field "login_status_form[uamip]" "$HTML_FILE")
UAMPORT=$(extract_hidden_field "login_status_form[uamport]" "$HTML_FILE")
LL=$(extract_hidden_field "login_status_form[ll]" "$HTML_FILE")
MYLOGIN=$(extract_hidden_field "login_status_form[myLogin]" "$HTML_FILE")
TOKEN=$(extract_hidden_field "login_status_form[_token]" "$HTML_FILE")

echo "Extracted challenge: $CHALLENGE"
echo "Extracted uamip: $UAMIP"
echo "Extracted uamport: $UAMPORT"
echo "Extracted ll: $LL (can be empty)"
echo "Extracted myLogin: $MYLOGIN (can be empty)"
echo "Extracted _token: $TOKEN"

# Validate critical fields
if [ -z "$CHALLENGE" ] || [ -z "$UAMIP" ] || [ -z "$UAMPORT" ] || [ -z "$TOKEN" ]; then
    echo "ERROR: One or more critical hidden fields (challenge, uamip, uamport, _token) could not be extracted. Exiting."
    exit 1
fi

# 4. Construct POST data
echo "Step 4: Constructing POST data payload."
# The form uses 'login_status_form[button]' for submission. No specific value is expected, so an empty string is used.
# All other fields are hidden inputs. Values are URL-encoded.
POST_DATA_RAW="login_status_form[button]=&login_status_form[challenge]=${CHALLENGE}&login_status_form[uamip]=${UAMIP}&login_status_form[uamport]=${UAMPORT}&login_status_form[ll]=${LL}&login_status_form[myLogin]=${MYLOGIN}&login_status_form[_token]=${TOKEN}"

# URL-encode the data. This is crucial for special characters.
# Bash does not have a built-in URL encoder, using sed for basic encoding
# Note: This sed command is a basic encoder and might not cover all edge cases, but is sufficient for common scenarios.
POST_DATA=$(echo "$POST_DATA_RAW" | sed -E 's/([^a-zA-Z0-9_.-])/\%\L\1/g')

echo "POST Data: $POST_DATA"

# 5. Submit the POST request
echo "Step 5: Submitting the POST request to $LANDING_URL..."
echo "Using cookies from $COOKIE_FILE"
POST_CURL_OUTPUT=$(curl $CURL_OPTIONS -v -X POST -d "$POST_DATA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LANDING_URL" 2>&1)
POST_STATUS=$(echo "$POST_CURL_OUTPUT" | grep -oP '^< HTTP/\d\.\d \K\d{3}' | tail -1)

echo "HTTP Status for POST request: $POST_STATUS"
echo "Curl output for POST request:"
echo "$POST_CURL_OUTPUT"

# Check if the POST was successful (e.g., a 200 OK or a redirect to a success page)
# Captive portals often redirect to the original request URL (detectportal.firefox.com) or a success page after login.
if [[ "$POST_STATUS" =~ ^3[0-9]{2}$ ]]; then
    echo "POST request resulted in a redirect ($POST_STATUS). This is often a good sign for successful login."
    FINAL_REDIRECT_URL=$(echo "$POST_CURL_OUTPUT" | grep -oP '^< Location: \K.*' | tail -1 | tr -d '\r')
    echo "Final effective URL after redirects: $FINAL_REDIRECT_URL"
    if [[ "$FINAL_REDIRECT_URL" == *detectportal.firefox.com* ]]; then
        echo "Successfully redirected back to portal detection URL, indicating successful authentication."
    else
        echo "Redirected to an unexpected URL: $FINAL_REDIRECT_URL. Login might be successful, proceeding with connectivity check."
    fi
elif [[ "$POST_STATUS" == "200" ]]; then
    echo "POST request returned 200 OK. No immediate redirect. Proceeding with connectivity check."
else
    echo "WARNING: POST request returned an unexpected status code: $POST_STATUS. Login might have failed."
    # Continue to connectivity check as some portals might enable internet without a final redirect or explicit success page.
fi

# 6. Connectivity check
echo "Step 6: Performing final connectivity check to 8.8.8.8..."
ping -c 3 8.8.8.8 >/dev/null

if [ $? -eq 0 ]; then
    echo "Connectivity check successful. You should now be online."
    rm -f "$COOKIE_FILE" "$HTML_FILE"
    exit 0
else
    echo "ERROR: Connectivity check failed. You are still not online."
    rm -f "$COOKIE_FILE" "$HTML_FILE"
    exit 1
fi

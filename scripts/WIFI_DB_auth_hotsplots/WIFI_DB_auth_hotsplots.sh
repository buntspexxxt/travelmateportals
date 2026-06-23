#!/bin/bash

# --- Configuration & Setup ---

# Create a temporary directory for cookies and HTML if it doesn't exist
TMP_DIR=$(mktemp -d)
COOKIE_FILE="${TMP_DIR}/cookies.txt"
HTML_FILE="${TMP_DIR}/portal_page.html"

# Enable verbose logging for debugging
set -e # Exit immediately if a command exits with a non-zero status.

echo "--- Captive Portal Login Script for WIFI_DB_auth_hotsplots ---"
echo "Temporary directory created: ${TMP_DIR}"
echo "Cookie file: ${COOKIE_FILE}"
echo "HTML file: ${HTML_FILE}"

# --- Step 1: Initial Probe to Get Landing Page URL ---
echo "\n[STEP 1/3] Probing http://detectportal.firefox.com/ to get the captive portal landing URL..."

# Use curl to follow redirects and capture the effective URL.
# -L: Follow redirects
# -s: Silent mode (don't show progress meter or error messages)
# -o /dev/null: Discard output
# -w %{url_effective}: Print the effective URL after all redirects
EFFECTIVE_URL=$(curl -L -s -o /dev/null -w "%{url_effective}" "http://detectportal.firefox.com/")
CURL_STATUS=$?

if [ $CURL_STATUS -ne 0 ]; then
    echo "ERROR: Initial probe failed with curl status code $CURL_STATUS."
    rm -rf "$TMP_DIR"
    exit 1
fi

if [ -z "$EFFECTIVE_URL" ]; then
    echo "ERROR: No effective URL found after probing. Portal might not be active or reachable."
    rm -rf "$TMP_DIR"
    exit 1
fi

LANDING_URL="$EFFECTIVE_URL"
echo "Landing URL identified: ${LANDING_URL}"

# --- Step 2: Download the Portal Page and Extract Hidden Fields ---
echo "\n[STEP 2/3] Downloading the portal page to extract hidden form fields..."

# Download the HTML page and save cookies.
# -c: Write cookies to file
# -b: Read cookies from file (for subsequent requests, though not strictly needed here)
# -o: Save output to file
# -s: Silent mode
curl -L -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -o "$HTML_FILE" "$LANDING_URL"
CURL_STATUS=$?

if [ $CURL_STATUS -ne 0 ]; then
    echo "ERROR: Failed to download portal page with curl status code $CURL_STATUS."
    rm -rf "$TMP_DIR"
    exit 1
fi

if [ ! -f "$HTML_FILE" ] || [ ! -s "$HTML_FILE" ]; then
    echo "ERROR: Downloaded HTML file is empty or missing."
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "Portal HTML downloaded to ${HTML_FILE}. Extracting hidden fields..."

# Extract hidden input field values using grep with Perl-compatible regex.
# This looks for specific name attributes and extracts their 'value'.
challenge=$(grep -oP 'name="login_status_form\[challenge\]" value="\K[^\"]+' "$HTML_FILE" || echo '')
uamip=$(grep -oP 'name="login_status_form\[uamip\]" value="\K[^\"]+' "$HTML_FILE" || echo '')
uamport=$(grep -oP 'name="login_status_form\[uamport\]" value="\K[^\"]+' "$HTML_FILE" || echo '')
ll=$(grep -oP 'name="login_status_form\[ll\]" value="\K[^\"]+' "$HTML_FILE" || echo '')
myLogin=$(grep -oP 'name="login_status_form\[myLogin\]" value="\K[^\"]+' "$HTML_FILE" || echo '')
_token=$(grep -oP 'name="login_status_form\[_token\]" value="\K[^\"]+' "$HTML_FILE" || echo '')

# Validate critical fields
if [ -z "$_token" ]; then
    echo "ERROR: Could not extract _token from the HTML. This is a critical field."
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "Extracted fields:"
echo "  challenge: '${challenge}'"
echo "  uamip: '${uamip}'"
echo "  uamport: '${uamport}'"
echo "  ll: '${ll}'"
echo "  myLogin: '${myLogin}'"
echo "  _token: (hidden)"

# Construct the POST data payload.
# The form also submits a button with its name, even if no explicit value is given.
POST_DATA="login_status_form[button]=&login_status_form[challenge]=${challenge}&login_status_form[uamip]=${uamip}&login_status_form[uamport]=${uamport}&login_status_form[ll]=${ll}&login_status_form[myLogin]=${myLogin}&login_status_form[_token]=${_token}"
echo "POST data constructed."

# --- Step 3: Submit the Login Form ---
echo "\n[STEP 3/3] Submitting the login form..."
echo "Posting to URL: ${LANDING_URL}"
echo "POST Payload: ${POST_DATA}"

# Submit the POST request.
# -v: Verbose output for debugging HTTP headers
# -L: Follow redirects
# -c: Write cookies
# -b: Read cookies
# -X POST: Specify POST method
# -d: Data to send in POST body
LOGIN_RESPONSE=$(curl -L -v -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST -d "$POST_DATA" "$LANDING_URL" 2>&1)
CURL_STATUS=$?

echo "HTTP Response (verbose):"
echo "${LOGIN_RESPONSE}"

if [ $CURL_STATUS -ne 0 ]; then
    echo "ERROR: Login POST request failed with curl status code $CURL_STATUS."
    rm -rf "$TMP_DIR"
    exit 1
fi

# Check if the response indicates success (e.g., redirect to success page or external site)
# This is a generic check; you might need to tailor it based on actual success responses.
if echo "$LOGIN_RESPONSE" | grep -q "Location"; then
    FINAL_LOCATION=$(echo "$LOGIN_RESPONSE" | grep "< Location: " | tail -1 | awk '{print $3}' | tr -d '\r')
    echo "Redirect detected to: ${FINAL_LOCATION}"
    # More specific checks could go here, e.g., if FINAL_LOCATION contains 'success' or 'google.com'
else
    echo "No obvious redirect detected. Check the full response for success indicators."
fi

echo "Login process completed. Cleaning up temporary files."
rm -rf "$TMP_DIR"

# --- Step 4: Verify Internet Connectivity ---
echo "\n[STEP 4/4] Verifying internet connectivity by pinging 8.8.8.8..."

ping -c 3 8.8.8.8 >/dev/null

if [ $? -eq 0 ]; then
    echo "SUCCESS: Internet connectivity confirmed."
    exit 0
else
    echo "FAILURE: Could not connect to 8.8.8.8. Internet access not established."
    exit 1
fi

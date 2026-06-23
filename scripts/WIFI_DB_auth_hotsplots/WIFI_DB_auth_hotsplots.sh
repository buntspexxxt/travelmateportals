#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration Variables ---
# The initial URL to check for captive portal redirection.
# This URL is usually a simple HTTP site that will trigger a redirect to the portal.
CHECK_URL="http://detectportal.firefox.com/"

# Temporary directory for storing cookies and HTML content.
TEMP_DIR="/tmp/portal_login_$(date +%s)"
COOKIE_JAR="$TEMP_DIR/cookies.txt"
HTML_FILE="$TEMP_DIR/portal_page.html"

# User-Agent string to mimic a web browser.
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# --- Setup Temporary Directory ---
echo "--- Setting up temporary directory ---"
mkdir -p "$TEMP_DIR"
echo "Temporary directory created: $TEMP_DIR"
echo "Cookie jar path: $COOKIE_JAR"
echo "HTML file path: $HTML_FILE"

# --- Step 1: Detect Captive Portal and Get Landing URL ---
echo "--- Step 1: Detecting captive portal and obtaining landing URL ---"
echo "Attempting to reach '$CHECK_URL' to trigger redirect."
echo "Running curl to get effective URL and initial cookies (output redirected for clarity):"
echo "  curl -sL -D - -c \"$COOKIE_JAR\" \"$CHECK_URL\" -w \"%{url_effective}\n\" -o /dev/null"

# Execute curl to get the final effective URL and initial cookies.
# -s: Silent mode. -L: Follow redirects.
# -D -: Dump headers to stderr. -c: Save cookies.
# -w "% {url_effective}\n": Print the effective URL after all redirects to stdout.
# -o /dev/null: Discard the actual HTML content for this step.
CURL_OUTPUT=$(curl -sL -D - -c "$COOKIE_JAR" "$CHECK_URL" -w "%{url_effective}\n" -o /dev/null 2>&1)
CURL_EXIT_CODE=$?

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Curl failed to detect portal with exit code $CURL_EXIT_CODE. Exiting."
    echo "CURL Output: $CURL_OUTPUT"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Extract the effective landing URL from the curl output (last line for -w option).
LANDING_URL=$(echo "$CURL_OUTPUT" | tail -n 1)

if [ -z "$LANDING_URL" ]; then
    echo "ERROR: Failed to obtain landing URL from curl output. Exiting."
    echo "CURL Output: $CURL_OUTPUT"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Effective Landing URL: $LANDING_URL"
echo "Initial cookies (if any) saved to: $COOKIE_JAR"

# Extract the base URL (scheme and hostname) from the LANDING_URL.
BASE_URL=$(echo "$LANDING_URL" | grep -oP '^https?://[^/]+')
if [ -z "$BASE_URL" ]; then
    echo "ERROR: Could not extract base URL from landing URL. Exiting."
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "Extracted Base URL: $BASE_URL"

# --- Step 2: Download the Portal Page and Extract Form Data ---
echo "--- Step 2: Downloading the portal page and extracting form data ---"
echo "Downloading HTML from: '$LANDING_URL' using saved cookies."
echo "Running: curl -v -L -b \"$COOKIE_JAR\" -c \"$COOKIE_JAR\" -A \"$USER_AGENT\" -o \"$HTML_FILE\" \"$LANDING_URL\""

# Download the HTML content of the portal page, saving headers for debugging (-v).
# -b: Use cookies from jar. -c: Save updated cookies to jar.
# -A: Set User-Agent. -o: Save HTML to file.
CURL_RESPONSE=$(curl -v -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" -A "$USER_AGENT" -o "$HTML_FILE" "$LANDING_URL" 2>&1)
CURL_EXIT_CODE=$?

echo "Curl command output for page download:"
echo "$CURL_RESPONSE"

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Failed to download portal page. Curl exit code: $CURL_EXIT_CODE. Exiting."
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "Portal HTML downloaded to: $HTML_FILE"

HTML_CONTENT=$(cat "$HTML_FILE")
if [ -z "$HTML_CONTENT" ]; then
    echo "ERROR: Downloaded HTML content is empty. Exiting."
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "--- Parsing HTML for hidden form fields ---"
# Extract values of hidden input fields dynamically from the downloaded HTML.
# We use grep with Perl-compatible regular expressions (-oP) for robust extraction.
CHALLENGE=$(echo "$HTML_CONTENT" | grep -oP 'name="login_status_form\[challenge\]" value="\K[^"]*')
UAMIP=$(echo "$HTML_CONTENT" | grep -oP 'name="login_status_form\[uamip\]" value="\K[^"]*')
UAMPORT=$(echo "$HTML_CONTENT" | grep -oP 'name="login_status_form\[uamport\]" value="\K[^"]*')
LL=$(echo "$HTML_CONTENT" | grep -oP 'name="login_status_form\[ll\]" value="\K[^"]*')
MYLOGIN=$(echo "$HTML_CONTENT" | grep -oP 'name="login_status_form\[myLogin\]" value="\K[^"]*')
TOKEN=$(echo "$HTML_CONTENT" | grep -oP 'name="login_status_form\[_token\]" value="\K[^"]*')

# The submit button's name and its display text are sent as part of the form data.
BUTTON_NAME="login_status_form[button]"
BUTTON_TEXT_VALUE="Jetzt kostenlos surfen" # Directly from HTML content

echo "Extracted CHALLENGE: '$CHALLENGE'"
echo "Extracted UAMIP: '$UAMIP'"
echo "Extracted UAMPORT: '$UAMPORT'"
echo "Extracted LL: '$LL' (can be empty)"
echo "Extracted MYLOGIN: '$MYLOGIN' (can be empty)"
echo "Extracted TOKEN: '$TOKEN'"
echo "Button Name: '$BUTTON_NAME'"
echo "Button Value: '$BUTTON_TEXT_VALUE'"

# Validate that essential fields were found.
if [ -z "$CHALLENGE" ] || [ -z "$UAMIP" ] || [ -z "$UAMPORT" ] || [ -z "$TOKEN" ]; then
    echo "ERROR: One or more essential hidden fields (challenge, uamip, uamport, _token) not found in HTML. Exiting."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# --- Step 3: Submit the Login Form ---
echo "--- Step 3: Submitting the login form ---"

# Construct the POST data payload. Curl will automatically URL-encode these values.
POST_DATA=$(printf "%s=%s&%s=%s&%s=%s&%s=%s&%s=%s&%s=%s&%s=%s" \
    "login_status_form[challenge]" "${CHALLENGE}" \
    "login_status_form[uamip]" "${UAMIP}" \
    "login_status_form[uamport]" "${UAMPORT}" \
    "login_status_form[ll]" "${LL}" \
    "login_status_form[myLogin]" "${MYLOGIN}" \
    "login_status_form[_token]" "${TOKEN}" \
    "${BUTTON_NAME}" "${BUTTON_TEXT_VALUE}")

echo "Posting data to: '$LANDING_URL'"
echo "POST Data: $POST_DATA"
echo "Running: curl -v -L -b \"$COOKIE_JAR\" -c \"$COOKIE_JAR\" -A \"$USER_AGENT\" -X POST -d \"$POST_DATA\" \"$LANDING_URL\""

# Submit the POST request.
# -X POST: Specify POST method. -d: Provide POST data.
CURL_RESPONSE=$(curl -v -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" -A "$USER_AGENT" -X POST -d "$POST_DATA" "$LANDING_URL" 2>&1)
CURL_EXIT_CODE=$?

echo "Curl command output for form submission:"
echo "$CURL_RESPONSE"

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Failed to submit login form. Curl exit code: $CURL_EXIT_CODE. Exiting."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Check for common success indicators in the final curl response.
if echo "$CURL_RESPONSE" | grep -q "Location:"; then
    FINAL_REDIRECT_URL=$(echo "$CURL_RESPONSE" | grep -oP '(?<=< Location: ).*' | tail -n 1 | tr -d '\r')
    echo "Login form submission resulted in a redirect to: $FINAL_REDIRECT_URL"
elif echo "$CURL_RESPONSE" | grep -q "200 OK" && echo "$CURL_RESPONSE" | grep -qi "welcome\|success\|online\|successfully connected"; then
    echo "Login form submission appears to be successful (HTTP 200 OK and common success keywords found)."
else
    echo "WARNING: Login form submission status is ambiguous. Proceeding to final connectivity check."
fi

# --- Step 4: Final Connectivity Check ---
echo "--- Step 4: Performing final connectivity check ---"
echo "Attempting to ping 8.8.8.8 to verify internet connectivity..."
# Ping a reliable public IP address (Google's DNS) to confirm internet access.
ping -c 3 8.8.8.8 > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Connectivity check successful. You should now be online!"
    rm -rf "$TEMP_DIR"
    echo "Cleaned up temporary directory: $TEMP_DIR"
    exit 0
else
    echo "ERROR: Connectivity check failed. You might not be online after portal interaction."
    echo "Temporary directory '$TEMP_DIR' retained for debugging purposes."
    exit 1
fi

#!/bin/bash

# This script automates the login process for the 'Stadtwerke_Neuss_www_hotsplots' captive portal.
# It extracts dynamic parameters from the initial redirect URL and hidden form fields from the HTML.
# Logging is extensive to aid in debugging.

# --- Configuration Variables ---
COOKIE_FILE="/tmp/hotsplots_cookies.txt"
HTML_FILE="/tmp/hotsplots_login_page.html"
HEADERS_FILE="/tmp/hotsplots_headers.txt"
CURL_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# --- Function to log messages ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- Function to check internet connectivity ---
check_connectivity() {
    log_message "Checking internet connectivity..."
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        log_message "Internet connectivity established. Exiting with success."
        rm -f "$COOKIE_FILE" "$HTML_FILE" "$HEADERS_FILE" # Clean up temporary files
        exit 0
    else
        log_message "Internet connectivity FAILED. Exiting with error."
        rm -f "$COOKIE_FILE" "$HTML_FILE" "$HEADERS_FILE" # Clean up temporary files
        exit 1
    fi
}

# --- Main Script Logic ---

log_message "Starting Hotspots captive portal login script."

# Step 1: Initial request to trigger the captive portal redirect and capture cookies/headers/HTML.
log_message "Performing initial request to http://detectportal.firefox.com/ to get the landing page and redirect details."
INITIAL_CURL_OUTPUT=$(curl -L -s -o "$HTML_FILE" -D "$HEADERS_FILE" -c "$COOKIE_FILE" -A "$CURL_USER_AGENT" "http://detectportal.firefox.com/" 2>&1)

if [ $? -ne 0 ]; then
    log_message "ERROR: Initial curl request failed. Output: $INITIAL_CURL_OUTPUT"
    exit 1
fi

log_message "Initial request successful. HTML saved to '$HTML_FILE', headers to '$HEADERS_FILE'."

# Extract the final landing URL after all redirects
LANDING_URL=$(grep -i '^Location:' "$HEADERS_FILE" | tail -n 1 | awk '{print $2}' | tr -d '\r')

if [ -z "$LANDING_URL" ]; then
    log_message "WARNING: Could not find 'Location' header in '$HEADERS_FILE'. Attempting to use the final URL from a follow-up request to get actual content."
    # If Location header is not found, it means curl -L already landed on the page.
    # We need the actual URL curl ended up on. Use --stderr - to get the effective URL.
    LANDING_URL=$(curl -L -s -o /dev/null -w '%{url_effective}\n' "http://detectportal.firefox.com/" -A "$CURL_USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE")
    if [ -z "$LANDING_URL" ]; then
        log_message "ERROR: Failed to determine the final landing URL. Exiting."
        exit 1
    fi
    log_message "Effective landing URL determined: $LANDING_URL"
fi

log_message "Landing URL: $LANDING_URL"

# Extract base domain from the landing URL
BASE_DOMAIN=$(echo "$LANDING_URL" | awk -F'/' '{print $3}')
log_message "Base domain: $BASE_DOMAIN"

# Extract the form action URL
FORM_ACTION_URL=$(grep -oP '<form\s+method="post"\s+action="\K[^\"]+' "$HTML_FILE" | head -n 1)

if [ -z "$FORM_ACTION_URL" ]; then
    log_message "ERROR: Could not find the form action URL in '$HTML_FILE'. Exiting."
    exit 1
fi
log_message "Form action URL: $FORM_ACTION_URL"

# Step 2: Extract dynamic parameters from the landing URL (CoovaChilli style parameters).
log_message "Extracting dynamic parameters from the landing URL query string."

QUERY_STRING=$(echo "$LANDING_URL" | grep -o '?.*' | cut -c 2-)

if [ -z "$QUERY_STRING" ]; then
    log_message "WARNING: No query string found in LANDING_URL. This might be an issue if parameters like mac/challenge are required."
else
    log_message "Query String from Landing URL: $QUERY_STRING"
    # Decode URL-encoded characters in the query string (especially userurl)
    QUERY_STRING_DECODED=$(echo "$QUERY_STRING" | sed 's/%3a/:/g; s/%2f/\//g; s/%3d/=/g; s/%26/\&/g')
    log_message "Query String (decoded): $QUERY_STRING_DECODED"
fi

# Initialize POST data with URL parameters
POST_DATA="$QUERY_STRING_DECODED"

# Step 3: Extract hidden form fields from the HTML.
log_message "Extracting hidden form fields from '$HTML_FILE'."

# Function to extract hidden input value
get_hidden_field() {
    grep -oP "<input type=\"hidden\" name=\"$1\" value=\"\K[^\"]+" "$HTML_FILE" | head -n 1
}

HAVETERMS=$(get_hidden_field "haveTerms")
MYLOGIN=$(get_hidden_field "myLogin")
LL=$(get_hidden_field "ll")
CUSTOM=$(get_hidden_field "custom")

# Optional: Extracting challenge, uamip, uamport, userurl, nasid from HTML too, for robustness
# These are often also in the URL, but if the form overwrites them, HTML is definitive.
CHALLENGE_FROM_HTML=$(get_hidden_field "challenge")
UAMIP_FROM_HTML=$(get_hidden_field "uamip")
UAMPORT_FROM_HTML=$(get_hidden_field "uamport")
USERURL_FROM_HTML=$(get_hidden_field "userurl")
NASID_FROM_HTML=$(get_hidden_field "nasid")

# Append HTML form fields to POST_DATA. Prioritize form fields if they exist.
append_post_data() {
    local field_name="$1"
    local field_value="$2"
    if [ -n "$field_value" ]; then
        if [ -n "$POST_DATA" ]; then
            POST_DATA="${POST_DATA}&${field_name}=${field_value}"
        else
            POST_DATA="${field_name}=${field_value}"
        fi
        log_message "Added form field: ${field_name}=${field_value}"
    else
        log_message "INFO: Form field '${field_name}' not found in HTML or is empty."
    fi
}

# Ensure common parameters are present, preferring values from the form if available
# The query string already has most of these, but this ensures form-specific hidden fields are added.
if ! echo "$POST_DATA" | grep -q "challenge="; then append_post_data "challenge" "$CHALLENGE_FROM_HTML"; fi
if ! echo "$POST_DATA" | grep -q "uamip="; then append_post_data "uamip" "$UAMIP_FROM_HTML"; fi
if ! echo "$POST_DATA" | grep -q "uamport="; then append_post_data "uamport" "$UAMPORT_FROM_HTML"; fi
if ! echo "$POST_DATA" | grep -q "userurl="; then append_post_data "userurl" "$USERURL_FROM_HTML"; fi
if ! echo "$POST_DATA" | grep -q "nasid="; then append_post_data "nasid" "$NASID_FROM_HTML"; fi

append_post_data "haveTerms" "$HAVETERMS"
append_post_data "myLogin" "$MYLOGIN"
append_post_data "ll" "$LL"
append_post_data "custom" "$CUSTOM"

# Add the checkbox and submit button values
if [ -n "$POST_DATA" ]; then
    POST_DATA="${POST_DATA}&termsOK=on&button=kostenlos+einloggen"
else
    POST_DATA="termsOK=on&button=kostenlos+einloggen"
fi
log_message "Added checkbox and submit button fields."

log_message "Final POST data to be sent: $POST_DATA"

# Step 4: Submit the login form.
log_message "Submitting login form to $FORM_ACTION_URL."

LOGIN_RESPONSE=$(curl -L -v -X POST \
    -d "$POST_DATA" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Origin: https://$BASE_DOMAIN" \
    -H "Referer: $LANDING_URL" \
    -A "$CURL_USER_AGENT" \
    -c "$COOKIE_FILE" \
    -b "$COOKIE_FILE" \
    "$FORM_ACTION_URL" 2>&1)

LOGIN_HTTP_STATUS=$(echo "$LOGIN_RESPONSE" | grep -i '< HTTP/1.' | awk '{print $2}' | tail -n 1)

log_message "Login request completed."
log_message "HTTP Status Code: $LOGIN_HTTP_STATUS"
log_message "Full Curl Output (Login Response):
$LOGIN_RESPONSE"

if [[ "$LOGIN_HTTP_STATUS" =~ ^2 ]]; then
    log_message "Login request appears to have returned a success status (2xx)."
else
    log_message "WARNING: Login request returned an unexpected HTTP status code: $LOGIN_HTTP_STATUS. Continuing to connectivity check."
fi

# Step 5: Check for internet connectivity after login.
check_connectivity

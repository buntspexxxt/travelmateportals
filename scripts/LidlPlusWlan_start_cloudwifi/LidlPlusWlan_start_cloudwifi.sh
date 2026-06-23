#!/bin/bash

# This script automates login to the 'LidlPlusWlan_start_cloudwifi' captive portal.
# It extracts all necessary dynamic parameters from the landing URL and hidden form fields.

# --- Configuration --- CRITICAL: Do not modify these temporary file paths.
COOKIE_FILE="/tmp/lidl_cloudwifi_cookies.txt"
HTML_FILE="/tmp/lidl_cloudwifi_portal.html"

# --- Function for logging and error handling --- MANDATORY: Extensive logging.
log() {
    echo "LIDL_CLOUD_WIFI_PORTAL: $1"
}

error_exit() {
    log "ERROR: $1"
    # Clean up temporary files on error
    rm -f "$COOKIE_FILE" "$HTML_FILE"
    exit 1
}

# --- Initial Connectivity Check --- MANDATORY: Check if already connected.
log "Step 0: Performing initial connectivity check. If already connected, no portal action is needed."
ping -c 3 8.8.8.8 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    log "SUCCESS: Internet connectivity confirmed. No captive portal action needed."
    exit 0
else
    log "Initial connectivity check failed. Proceeding with captive portal login attempt."
fi

# --- Step 1: Make initial request to a known internet endpoint to get the captive portal landing URL --- MANDATORY: Dynamic URL extraction.
log "Step 1: Making initial request to a known internet endpoint (http://detectportal.firefox.com/) to obtain the captive portal's landing URL."
log "Using curl -L -s -o /dev/null -w \"%{url_effective}\" http://detectportal.firefox.com/"
LANDING_URL=$(curl -L -s -o /dev/null -w "%{url_effective}" http://detectportal.firefox.com/)
CURL_STATUS=$?

# MANDATORY: Capture and print all outputs.
if [ $CURL_STATUS -ne 0 ]; then
    error_exit "Initial curl request to detectportal.firefox.com failed with status $CURL_STATUS."
fi
log "Detected LANDING_URL: $LANDING_URL"

# If LANDING_URL is still the original detectportal URL, it means no redirect occurred, implies already connected.
if [[ -z "$LANDING_URL" || "$LANDING_URL" == "http://detectportal.firefox.com/" ]]; then
    log "LANDING_URL is unchanged. This suggests internet access is already available or portal did not redirect."
    # Redo the connectivity check, in case the first one was a fluke.
    ping -c 3 8.8.8.8 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        log "SUCCESS: Internet access confirmed after re-check, exiting successfully."
        exit 0
    else
        error_exit "No internet access and no portal redirect detected. Cannot proceed."
    fi
fi

# Extract base domain from LANDING_URL (e.g., https://start.cloudwifi.de) MANDATORY: Dynamic base domain.
BASE_DOMAIN=$(echo "$LANDING_URL" | sed -E 's|https?://([^/]+).*|\1|')
log "Extracted base domain: $BASE_DOMAIN"

# --- Step 2: Download the portal page and save cookies --- MANDATORY: Cookie handling.
log "Step 2: Downloading the captive portal page from $LANDING_URL to extract hidden form fields and capture session cookies."
log "Using: curl -s -v -L -c \"$COOKIE_FILE\" -b \"$COOKIE_FILE\" \"$LANDING_URL\" -o \"$HTML_FILE\""

# Capture full curl output (verbose headers + body redirected to file) for debugging.
CURL_OUTPUT=$(curl -s -v -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$LANDING_URL" -o "$HTML_FILE" 2>&1)
CURL_STATUS=$?
log "Curl command output for downloading portal page:"
echo "$CURL_OUTPUT"

if [ $CURL_STATUS -ne 0 ]; then
    error_exit "Failed to download portal page with status $CURL_STATUS."
fi
log "Portal page downloaded to $HTML_FILE. Cookies saved to $COOKIE_FILE."

# Verify HTML file content.
if [ ! -s "$HTML_FILE" ]; then
    error_exit "Downloaded HTML file ($HTML_FILE) is empty or does not exist."
fi
HTML_CONTENT=$(cat "$HTML_FILE")

# --- Step 3: Extract hidden form fields for the 'Easy Login' form (FX_loginform_0) --- MANDATORY: Dynamic hidden field extraction.
log "Step 3: Extracting hidden input fields from the 'FX_loginform_0' form in the downloaded HTML."

# Extract the specific form HTML for robustness.
FORM_HTML=$(echo "$HTML_CONTENT" | grep -oP '<form name="FX_loginform_0".*?</form>' || true)

if [ -z "$FORM_HTML" ]; then
    error_exit "Could not find form 'FX_loginform_0' in the HTML. Portal structure might have changed."
fi

# Extract all hidden input fields (name=value pairs) from the form.
HIDDEN_INPUTS=$(echo "$FORM_HTML" | \
    grep -oP '<input type="hidden" name="[^\"]+" value="[^\"]*"' | \
    sed -E 's/<input type="hidden" name="([^\"]+)" value="([^\"]*)".*/\1=\2/' || true)

if [ -z "$HIDDEN_INPUTS" ]; then
    error_exit "No hidden input fields found in 'FX_loginform_0'. Portal structure might have changed."
fi

log "Successfully extracted hidden inputs for login form:
$HIDDEN_INPUTS"

# Prepare POST data for curl. --data-urlencode handles URL encoding for each key=value pair.
POST_DATA_ARRAY=()
while IFS= read -r line; do
    POST_DATA_ARRAY+=("--data-urlencode" "$line")
done <<< "$HIDDEN_INPUTS"

# --- Step 4: Submit the login form --- MANDATORY: POST request.
log "Step 4: Submitting the login form to $LANDING_URL with extracted data and captured cookies."
log "Using: curl -s -v -L -c \"$COOKIE_FILE\" -b \"$COOKIE_FILE\" -X POST \"$LANDING_URL\" \"${POST_DATA_ARRAY[@]}\", expecting a redirect or success page."

# Execute POST request. -L to follow redirects, -v for verbose output.
LOGIN_RESPONSE_CURL_OUTPUT=$(curl -s -v -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$LANDING_URL" "${POST_DATA_ARRAY[@]}" 2>&1)
CURL_STATUS=$?
log "Curl command output for login POST request:"
echo "$LOGIN_RESPONSE_CURL_OUTPUT"

if [ $CURL_STATUS -ne 0 ]; then
    error_exit "Failed to submit login form with status $CURL_STATUS."
fi
log "Login POST request sent. Checking final outcome."

# --- Step 5: Verify Internet Connectivity --- MANDATORY: Final connectivity check.
log "Step 5: Verifying internet connectivity by pinging 8.8.8.8 after attempting login."
ping -c 3 8.8.8.8 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    log "SUCCESS: Internet connectivity confirmed. You should now have access."
    # Clean up temporary files on successful completion
    rm -f "$COOKIE_FILE" "$HTML_FILE"
    exit 0
else
    error_exit "Internet connectivity check failed. Login might not have been successful or portal requires further interaction."
fi

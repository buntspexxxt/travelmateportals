#!/bin/bash

# CRITICAL: Extensive logging is mandatory. Print before every step.
# CRITICAL: Capture and print all outputs. Use -v for curl or capture status/response.
# CRITICAL: NEVER hardcode MAC addresses, IP addresses, session IDs, challenge strings.
# CRITICAL: NEVER hardcode store-specific URL paths.
# CRITICAL: NEVER fill in fake credentials. Pass empty strings if required.
# CRITICAL: Extract hidden input values dynamically. (Not applicable here, no forms).
# CRITICAL: Use cookies (-c /tmp/c.txt -b /tmp/c.txt).
# CRITICAL: Always append a connectivity check.

# --- Configuration ---
COOKIE_JAR="/tmp/aldi_wlan_cookies.txt"
INITIAL_CHECK_URL="http://detectportal.firefox.com/"
CURL_TIMEOUT=15 # seconds for curl operations

# --- Logging Functions ---
log_info() {
    echo "INFO: $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "ERROR: $(date +'%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_curl_output() {
    local label="$1"
    local output="$2"
    echo "--- Start Curl Output ($label) ---"
    echo "$output"
    echo "--- End Curl Output ($label) ---"
}

# Function to URL-encode a string
urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded_string=""
    local pos c o
    for pos in $(seq 0 $((strlen - 1))); do
        c=${string:$pos:1}
        case "$c" in
            [-._~0-9a-zA-Z]) o="$c" ;;
            *)               o=$(printf '%%%02X' "'$c") ;;
        esac
        encoded_string+="$o"
    done
    echo "$encoded_string"
}

# --- Main Script ---

log_info "Starting ALDI SÜD WLAN login script."
log_info "Initializing cookie jar: $COOKIE_JAR"
touch "$COOKIE_JAR" # Ensure cookie jar exists

# Step 1: Discover the initial captive portal landing URL via redirect
log_info "Step 1: Checking initial connectivity and discovering portal landing URL from $INITIAL_CHECK_URL"
# Use -s to suppress progress meter, -L to follow redirects, -D /dev/stdout to capture headers,
# -o /dev/null to discard body, -w "\n%{redirect_url}" to print the final URL after redirects on a new line.
# We redirect stderr to stdout (2>&1) to capture all output (headers and the final URL) into a variable.
CURL_OUTPUT=$(curl -s -L -c "$COOKIE_JAR" -D /dev/stdout -o /dev/null -w "\n%{redirect_url}" "$INITIAL_CHECK_URL" --max-time "$CURL_TIMEOUT" 2>&1)

# The last line of CURL_OUTPUT will be the redirect_url due to -w "\n%{redirect_url}"
PORTAL_LANDING_URL=$(echo "$CURL_OUTPUT" | tail -1)
# Headers and status will be all lines before the last line
CURL_HEADERS_AND_STATUS=$(echo "$CURL_OUTPUT" | head -n -1)
CURL_STATUS_CODE=$(echo "$CURL_HEADERS_AND_STATUS" | grep -oP 'HTTP/\S+\s+\K\d{3}' | tail -1)

log_curl_output "Initial Redirect Check (Headers & Status)" "$CURL_HEADERS_AND_STATUS"

if [[ -z "$PORTAL_LANDING_URL" || "$CURL_STATUS_CODE" -ge 400 ]]; then
    log_error "Failed to get a valid redirect URL or initial request failed. Final HTTP Status: $CURL_STATUS_CODE, Captured Redirect URL: '$PORTAL_LANDING_URL'"
    rm -f "$COOKIE_JAR"
    exit 1
fi

log_info "Portal Landing URL discovered: $PORTAL_LANDING_URL"

# Extract base domain and splash path from the landing URL
BASE_DOMAIN=$(echo "$PORTAL_LANDING_URL" | sed -E 's/https?:\/\/([^\/]+)\/.* /\1/')
SPLASH_PATH=$(echo "$PORTAL_LANDING_URL" | sed -E 's/https?:\/\/[^\/]+(\/splash\/[^?]+)\?.*/\1/')

if [[ -z "$BASE_DOMAIN" || -z "$SPLASH_PATH" ]]; then
    log_error "Failed to extract BASE_DOMAIN or SPLASH_PATH from $PORTAL_LANDING_URL. BASE_DOMAIN: '$BASE_DOMAIN', SPLASH_PATH: '$SPLASH_PATH'"
    rm -f "$COOKIE_JAR"
    exit 1
fi

log_info "Extracted Base Domain: $BASE_DOMAIN"
log_info "Extracted Splash Path: $SPLASH_PATH"

# Step 2: Simulate the JavaScript's XMLHttpRequest HEAD request to the PORTAL_LANDING_URL
# The JS in the HTML makes a HEAD request to the current page (PORTAL_LANDING_URL) to get a 'Continue-Url' header.
log_info "Step 2: Performing HEAD request to '$PORTAL_LANDING_URL' to extract 'Continue-Url' header, as per JS logic."
# Use -I for HEAD request, -s for silent, -b to send cookies, -c to save cookies, --max-time for timeout
HEAD_RESPONSE_HEADERS=$(curl -s -I -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$PORTAL_LANDING_URL" --max-time "$CURL_TIMEOUT")
CURL_STATUS_CODE=$(echo "$HEAD_RESPONSE_HEADERS" | head -1 | awk '{print $2}')

log_curl_output "HEAD Request to Landing Page" "$HEAD_RESPONSE_HEADERS"

if [[ "$CURL_STATUS_CODE" -ne 200 ]]; then
    log_error "HEAD request to landing page failed with status code: $CURL_STATUS_CODE"
    rm -f "$COOKIE_JAR"
    exit 1
fi

FINAL_CONTINUE_URL=$(echo "$HEAD_RESPONSE_HEADERS" | grep -i '^Continue-Url:' | sed -E 's/Continue-Url:\s*(.*)/\1/' | tr -d '\r')

if [[ -z "$FINAL_CONTINUE_URL" ]]; then
    log_error "Failed to extract 'Continue-Url' header from HEAD request response. This header is crucial for login."
    rm -f "$COOKIE_JAR"
    exit 1
fi

log_info "Extracted Final Continue URL from header: $FINAL_CONTINUE_URL"

# URL-encode the FINAL_CONTINUE_URL for the final grant request
ENCODED_FINAL_CONTINUE_URL=$(urlencode "$FINAL_CONTINUE_URL")
log_info "URL-encoded Final Continue URL: $ENCODED_FINAL_CONTINUE_URL"

# Step 3: Construct and execute the final grant GET request
# The JavaScript constructs the grant URL using the extracted Continue-Url header.
GRANT_URL="https://${BASE_DOMAIN}${SPLASH_PATH}/grant?continue_url=${ENCODED_FINAL_CONTINUE_URL}"

log_info "Step 3: Sending GET request to grant access: $GRANT_URL"
# Use -s -L -v for verbose output including headers and redirects, -b/-c for cookies.
GRANT_RESPONSE=$(curl -s -L -v -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$GRANT_URL" --max-time "$CURL_TIMEOUT" 2>&1)
CURL_STATUS_CODE=$(echo "$GRANT_RESPONSE" | grep -oP 'HTTP/\S+\s+\K\d{3}' | tail -1)

log_curl_output "Grant Access Request" "$GRANT_RESPONSE"

if [[ "$CURL_STATUS_CODE" -ge 400 ]]; then
    log_error "Grant request failed with status code: $CURL_STATUS_CODE"
    rm -f "$COOKIE_JAR"
    exit 1
fi

log_info "Login sequence completed. Checking internet connectivity."

# Step 4: Connectivity check
log_info "Step 4: Performing connectivity check (ping 8.8.8.8)..."
if ping -c 3 8.8.8.8 >/dev/null; then
    log_info "Connectivity check successful. You should now have internet access."
    rm -f "$COOKIE_JAR" # Clean up cookies
    exit 0
else
    log_error "Connectivity check failed. Internet access may not be granted."
    rm -f "$COOKIE_JAR" # Clean up cookies
    exit 1
fi

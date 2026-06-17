#!/bin/sh

# This script automates login for the Telekom HotSpot captive portal.
# It attempts to select the "1 Tag" (1 Day) pass for internet access.
#
# IMPORTANT: This script is based on assumptions about the captive portal's API
# and login flow, as the provided HTML only shows the initial Angular app
# structure, not the actual form submission or API calls. If it doesn't work,
# you will need to capture the network requests (using browser developer tools)
# when manually logging in and adjust the LOGIN_API_ENDPOINT and LOGIN_PAYLOAD
# accordingly.

# Configuration
SSID="Telekom"
# PROBE_URL is used to detect if we are behind a captive portal.
# A common choice is a URL that returns 204 No Content for a successful connection.
# If it redirects, we're likely on a portal.
PROBE_URL="http://www.gstatic.com/generate_204"
# The initial portal URL. This is a common Telekom HotSpot URL, but will be
# dynamically updated if a redirect from PROBE_URL reveals a different one.
PORTAL_BASE_URL="https://hotspot.t-online.de" 
# The API endpoint for initiating a session with a voucher.
# This is a strong assumption without actual network captures.
LOGIN_API_ENDPOINT="/api/v1/sessions" # Common pattern for session creation
# The voucher ID for the "1 Tag" pass, as identified in the HTML.
# We assume this is the desired option for automated login.
VOUCHER_ID="PASS_86400_0_EUR"

# Log file for debugging
LOG_FILE="/tmp/telekom_hotspot_login.log"

# --- Functions ---

# Function to log messages to stdout and the log file
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Function to check if internet connectivity is available
check_internet() {
    log "Checking internet connectivity using $PROBE_URL..."
    # Attempt to fetch PROBE_URL. If it fails or returns a non-2xx status,
    # assume no internet or captive portal is active.
    if curl -s -o /dev/null --fail "$PROBE_URL"; then
        log "Internet is reachable."
        return 0 # Internet is up
    else
        log "Internet is not reachable or captive portal detected."
        return 1 # Internet is down or portal is active
    fi
}

# Function to get the current connected WiFi SSID
get_current_ssid() {
    local iface
    # Iterate through all wireless interfaces to find the active SSID
    if command -v iwinfo >/dev/null 2>&1; then
        for iface in $(iwinfo | grep -E '^[a-z0-9]+' | cut -d ' ' -f 1); do
            local current_ssid=$(iwinfo "$iface" ESSID 2>/dev/null | awk -F': "' '{print $2}' | tr -d '"')
            if [ -n "$current_ssid" ]; then
                echo "$current_ssid"
                return 0
            fi
        done
    else
        log "Warning: 'iwinfo' command not found. Cannot determine current SSID reliably."
    fi
    echo "" # Return empty if no SSID found
    return 1
}

# --- Main Script ---

log "--- Telekom HotSpot Login Script Started ---"

# 1. Check current SSID
CURRENT_SSID=$(get_current_ssid)
if [ -z "$CURRENT_SSID" ]; then
    log "Could not determine current SSID. Ensure WiFi is connected and 'iwinfo' is available."
    exit 1
fi

if [ "$CURRENT_SSID" != "$SSID" ]; then
    log "Connected to '$CURRENT_SSID', not the target SSID '$SSID'. Exiting."
    exit 0 # Not on the target network, nothing to do.
fi
log "Connected to target SSID '$SSID'."

# 2. Check internet connectivity
if check_internet; then
    log "Internet is already connected. No action needed."
    exit 0
fi

# 3. Captive portal detected, attempt login.

log "Attempting to obtain actual portal URL via redirect from probe..."
# Use curl to follow redirects from the PROBE_URL to find the captive portal's full URL.
# -L: Follow redirects
# -s: Silent mode
# -o /dev/null: Discard response body
# -w '%{url_effective}': Print the final URL after all redirects
PORTAL_REDIRECT_URL=$(curl -L -s -o /dev/null -w '%{url_effective}' "$PROBE_URL")

if [ -n "$PORTAL_REDIRECT_URL" ]; then
    # Extract only the base URL (scheme://host:port) from the effective URL
    # Example: "https://hotspot.t-online.de/start?param=value" -> "https://hotspot.t-online.de"
    PORTAL_BASE_URL=$(echo "$PORTAL_REDIRECT_URL" | awk -F'[/:]+' '{print $1"://"$2}')
    log "Detected portal base URL: $PORTAL_BASE_URL"
else
    log "Could not automatically determine portal URL. Using configured PORTAL_BASE_URL: $PORTAL_BASE_URL"
fi

# Temporary files for cookies and headers
COOKIE_JAR="/tmp/telekom_cookies.txt"
HEADERS_OUT="/tmp/telekom_headers.txt"

log "Performing initial GET request to '$PORTAL_BASE_URL' to establish session and get cookies..."
# We need to capture cookies from the initial request.
# -c "$COOKIE_JAR": Write received cookies to file
# -D "$HEADERS_OUT": Write response headers to file
# -o /dev/null: Discard HTML body
# -s: Silent
# -L: Follow redirects
# -A: Set User-Agent to mimic a browser
curl -s -L -c "$COOKIE_JAR" -D "$HEADERS_OUT" -o /dev/null \
    -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    "$PORTAL_BASE_URL"

if [ $? -ne 0 ]; then
    log "Initial GET request failed. Cannot proceed with login."
    rm -f "$COOKIE_JAR" "$HEADERS_OUT"
    exit 1
fi
log "Initial GET request successful. Cookies stored."

# 4. Construct and send POST request for login
log "Attempting POST request to login API endpoint: ${PORTAL_BASE_URL}${LOGIN_API_ENDPOINT}"

# The JSON payload to send for selecting the voucher.
LOGIN_PAYLOAD="{\"voucherId\":\"$VOUCHER_ID\"}"

# Perform the POST request to the API endpoint
# -X POST: Specify POST method
# -H "Content-Type: application/json": Set content type for JSON payload
# -H "Accept: application/json, text/plain, */*": Request JSON response
# -d "$LOGIN_PAYLOAD": Send the JSON payload
# -b "$COOKIE_JAR": Send previously obtained cookies with the request
# -c "$COOKIE_JAR": Update cookies from the POST response
# -A: Set User-Agent
# --compressed: Request compressed response (common for APIs)
# -L: Follow redirects (if the API redirects on success)
# Store the response for analysis
LOGIN_RESPONSE=$(curl -s -L -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/plain, */*" \
    -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -d "$LOGIN_PAYLOAD" \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    --compressed \
    "$PORTAL_BASE_URL$LOGIN_API_ENDPOINT")

LOGIN_STATUS=$?

# Clean up temporary cookie and header files
rm -f "$COOKIE_JAR" "$HEADERS_OUT"

if [ "$LOGIN_STATUS" -ne 0 ]; then
    log "POST login request failed with curl error $LOGIN_STATUS."
    log "Login API Response: $LOGIN_RESPONSE"
    exit 1
fi

log "POST login request completed."
log "Login API Response: $LOGIN_RESPONSE"

# 5. Verify login success
# This check is basic. A more robust script would parse the JSON response
# for specific success indicators (e.g., using `jsonfilter`).
if echo "$LOGIN_RESPONSE" | grep -qi "success" || \
   echo "$LOGIN_RESPONSE" | grep -qi "ok" || \
   echo "$LOGIN_RESPONSE" | grep -qi "loggedIn"; then
    log "Login API response suggests success."
else
    log "Login API response did NOT clearly indicate success."
fi

# Final check for internet connectivity after the login attempt
if check_internet; then
    log "Successfully logged into Telekom HotSpot!"
    exit 0
else
    log "Login attempt completed, but internet is still not reachable."
    log "It's possible the API endpoint or payload is incorrect, or further steps are required."
    exit 1
fi

# JSON_LIMITS: {"limit_type": "TIME", "limit_value": 24, "unit": "hours", "description": "1 Tag pass, no data volume limit"}
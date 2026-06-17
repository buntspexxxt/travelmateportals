#!/bin/sh

# This script automates login for the "-Rheinpark-Center free Wifi" captive portal.
# It assumes your OpenWrt router is already connected to the Wi-Fi network,
# but internet access is blocked by the captive portal.
#
# Requirements:
# - `wget` (preferably `wget-ssl` for HTTPS support and `--no-check-certificate`)
#   or `uclient-fetch` with `ca-bundle` installed if using default HTTP-only `wget`.
#   This script assumes `wget` with `--no-check-certificate` support.
# - `grep`, `awk` (usually present on OpenWrt)
# - `logger` (usually present on OpenWrt)

# --- Configuration ---
# Common URLs to check for connectivity and trigger the portal.
# The connectivity test URL is used by many OS to detect internet access.
CONNECTIVITY_TEST_URL="http://www.msftconnecttest.com/connecttest.txt"
# A plain HTTP site. Accessing this often triggers a redirect to the captive portal.
PORTAL_TRIGGER_URL="http://neverssl.com"

# Temporary file to store HTML content fetched from the portal.
TEMP_HTML_FILE="/tmp/captive_portal_temp_$(date +%s).html"

# Logger function to output to syslog and console.
log() {
    logger -t "CaptivePortalLogin" "$@"
    echo "$@"
}

# Function to check for internet connectivity.
# Returns 0 if online, 1 if not.
check_connectivity() {
    log "Checking internet connectivity..."
    # Attempt to download a known external file.
    # -q: quiet (no output to stdout/stderr except errors)
    # -O /dev/null: output to /dev/null (discard content)
    # --no-check-certificate: crucial for captive portals as they often use
    #                         self-signed or invalid HTTPS certificates.
    #                         Remove if your 'wget' does not support it (e.g., uclient-fetch).
    #                         If using uclient-fetch, consider installing 'ca-bundle' or
    #                         using `--no-verify-peer` if available (not recommended for general security).
    if wget -q -O /dev/null --no-check-certificate "$CONNECTIVITY_TEST_URL"; then
        log "Connectivity test passed. Internet appears to be accessible."
        return 0
    else
        log "Connectivity test failed. Likely behind a captive portal or no network."
        return 1
    fi
}

# Function to perform the captive portal login process.
# Returns 0 on success, 1 on failure.
perform_login() {
    log "Attempting to log in to the captive portal..."

    # Step 1: Trigger the portal and get the initial HTML.
    # Requesting a plain HTTP site like neverssl.com often forces a redirect
    # to the captive portal's main page. We follow these redirects and save
    # the final HTML.
    log "Fetching initial captive portal page from $PORTAL_TRIGGER_URL..."
    if ! wget -q -O "$TEMP_HTML_FILE" --no-check-certificate "$PORTAL_TRIGGER_URL"; then
        log "ERROR: Could not fetch initial portal page from $PORTAL_TRIGGER_URL."
        rm -f "$TEMP_HTML_FILE" # Clean up temp file
        return 1
    fi

    log "Initial page fetched. Parsing for the login redirection URL..."

    # Step 2 & 3: Extract the `FX_redirect` call and the actual login URL.
    # The provided HTML contains a JavaScript call to FX_redirect.
    # Example: FX_redirect('MAC1', 'MAC2', 'LOGIN_URL', 'CONNECTTEST_URL', '', 'no');
    # We need the third argument, which is the actual login URL.
    # Using grep to find the line containing FX_redirect, then awk to extract the 6th field
    # when splitting by the single quote character.
    LOGIN_URL=$(grep "FX_redirect(" "$TEMP_HTML_FILE" | head -n 1 | awk -F"'" '{print $6}')

    if [ -z "$LOGIN_URL" ]; then
        log "ERROR: Could not extract login URL from the page. 'FX_redirect' call not found or malformed."
        rm -f "$TEMP_HTML_FILE" # Clean up temp file
        return 1
    fi

    log "Extracted login URL: $LOGIN_URL"
    
    # Step 4: Make a request to the extracted login URL.
    # For many Mikrotik-based captive portals, simply visiting this URL with a GET request
    # is sufficient to acknowledge terms and gain access for the device's MAC address.
    log "Visiting the extracted login URL to complete authentication..."
    if ! wget -q -O /dev/null --no-check-certificate "$LOGIN_URL"; then
        log "ERROR: Failed to visit the login URL: $LOGIN_URL."
        rm -f "$TEMP_HTML_FILE" # Clean up temp file
        return 1
    fi

    log "Login request sent. Waiting a few seconds for the portal to process the request..."
    sleep 5 # Give the portal server some time to register the login and update status.

    rm -f "$TEMP_HTML_FILE" # Clean up the temporary HTML file.
    log "Login process finished."
    return 0
}

# --- Main Script Logic ---
log "Starting captive portal login script for SSID: -Rheinpark-Center free Wifi"

# First, check if we are already online.
if check_connectivity; then
    log "Internet connectivity already present. No captive portal login needed at this time."
else
    log "No internet connectivity detected. Proceeding with captive portal login attempt."
    if perform_login; then
        log "Captive portal login sequence initiated. Re-checking internet connectivity..."
        # After attempting login, check connectivity again to verify success.
        if check_connectivity; then
            log "Successfully logged in to the captive portal and internet is now accessible!"
        else
            log "Login sequence completed, but internet connectivity is still not detected. Manual intervention might be needed."
        fi
    else
        log "Captive portal login process failed entirely."
    fi
fi

# JSON_LIMITS: {"info": "No bandwidth or time limits were mentioned in the provided HTML/JS content."}
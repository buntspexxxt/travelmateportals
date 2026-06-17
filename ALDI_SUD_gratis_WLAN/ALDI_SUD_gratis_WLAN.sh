#!/bin/sh

# This script automates login for the ALDI SÜD gratis WLAN captive portal.
# It is designed to be compatible with OpenWrt's 'ash' shell and common utilities.

# Configuration
SSID_TO_CHECK="ALDI SÜD gratis WLAN"
# A reliable URL to test for internet connectivity.
# Firefox uses this, and it typically returns "success" if there's no portal.
TEST_URL="http://detectportal.firefox.com/success.txt"
EXPECTED_TEST_RESPONSE="success"
# Base URL for the grant request, extracted from the HTML's JavaScript.
GRANT_BASE_URL="https://eu.network-auth.com/splash/bs-qtcsd.7.1097/grant?continue_url="

# --- Logging function ---
log() {
    logger -t "captive-portal-login" "$@"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $@"
}

# --- Function to check if we are connected to the target SSID ---
is_connected_to_target_ssid() {
    log "Checking current wireless connectivity..."
    
    # Get a list of all wireless device names (e.g., wlan0, wlan0-1, etc.)
    # from 'iwinfo' output.
    IFACE_NAMES=$(iwinfo | awk '/^[a-zA-Z0-9_-]+[ ]+ESSID:/ {print $1}')
    
    FOUND_SSID=""
    for iface in $IFACE_NAMES; do
        # Check if the interface is in client mode
        MODE=$(iwinfo "$iface" info 2>/dev/null | grep "Mode:" | awk '{print $2}')
        if [ "$MODE" = "Client" ]; then
            # If in client mode, get its associated SSID from 'assoclist' output.
            # Example line: ESSID: "ALDI SÜD gratis WLAN"
            CURRENT_SSID=$(iwinfo "$iface" assoclist 2>/dev/null | grep -o "ESSID: \".*\"" | head -n 1 | cut -d '"' -f 2)
            if [ -n "$CURRENT_SSID" ]; then
                FOUND_SSID="$CURRENT_SSID"
                break # Found the SSID on a client interface, no need to check others
            fi
        fi
    done

    if [ -z "$FOUND_SSID" ]; then
        log "Could not determine current SSID from any client interface."
        return 1
    fi

    log "Current connected SSID: \"$FOUND_SSID\""
    if [ "$FOUND_SSID" = "$SSID_TO_CHECK" ]; then
        return 0 # Connected to the target SSID
    else
        log "Connected to a different SSID: \"$FOUND_SSID\" instead of \"$SSID_TO_CHECK\"."
        return 1
    fi
}

# --- Function to check for active internet access ---
check_internet_access() {
    log "Checking internet access via $TEST_URL..."
    # Use curl with a short timeout to prevent hanging.
    # '--interface "wan"' tries to force traffic through the WAN interface.
    # This is a common setup where the client interface (e.g., wlan0-1) is part of the 'wan' logical interface/zone.
    if curl --interface "wan" -s --max-time 10 "${TEST_URL}" | grep -q "${EXPECTED_TEST_RESPONSE}"; then
        log "Internet access confirmed."
        return 0
    else
        log "No internet access or portal detected."
        return 1
    fi
}

# --- Function to get the captive portal URL ---
get_portal_url() {
    log "Attempting to get captive portal URL..."
    # Follow redirects from TEST_URL to find the portal page.
    # '-o /dev/null' discards the response body.
    # '-w "%{url_effective}"' prints the final URL after all redirects.
    PORTAL_URL=$(curl --interface "wan" -s -L -o /dev/null -w "%{url_effective}" --max-time 15 "${TEST_URL}")

    if [ -z "$PORTAL_URL" ] || echo "$PORTAL_URL" | grep -q "${TEST_URL}"; then
        log "Could not determine portal URL. Effective URL is still the test URL or empty."
        return 1
    fi

    # Check if the URL is from the expected domain to ensure we're on the ALDI SÜD portal.
    if ! echo "$PORTAL_URL" | grep -q "eu.network-auth.com"; then
        log "Detected portal URL '${PORTAL_URL}' does not seem to be from ALDI SÜD portal (expected eu.network-auth.com)."
        return 1
    fi

    echo "$PORTAL_URL"
    return 0
}

# --- Function to extract the 'Continue-Url' header from the portal page ---
get_continue_url_header() {
    PORTAL_PAGE_URL="$1"
    log "Making HEAD request to ${PORTAL_PAGE_URL} to get 'Continue-Url' header..."

    # Use curl to get headers only (-I).
    HEADERS=$(curl --interface "wan" -s -I --max-time 15 "${PORTAL_PAGE_URL}")
    
    # Extract the 'Continue-Url' header, case-insensitive.
    # 'sed' removes the header name, leading/trailing whitespace, and carriage return.
    CONTINUE_URL=$(echo "$HEADERS" | grep -i "^Continue-Url:" | head -n 1 | sed -e 's/^Continue-Url: //i' -e 's/^[ \t]*//' -e 's/[ \t]*$//' -e 's/\r$//')

    if [ -z "$CONTINUE_URL" ]; then
        log "Failed to extract 'Continue-Url' header."
        log "Headers received:\n${HEADERS}"
        return 1
    fi

    echo "$CONTINUE_URL"
    return 0
}

# --- Function to perform the actual login ---
perform_login() {
    PORTAL_URL="$1"
    
    # Get the dynamic continue_url from the portal page's HEAD request response.
    # This is crucial as per the JavaScript analysis in the HTML.
    DYNAMIC_CONTINUE_URL=$(get_continue_url_header "${PORTAL_URL}")
    if [ $? -ne 0 ]; then
        log "Login failed: Could not get dynamic continue URL from portal page."
        return 1
    fi
    log "Extracted dynamic continue_url: ${DYNAMIC_CONTINUE_URL}"

    # Construct the final grant URL.
    # The DYNAMIC_CONTINUE_URL is expected to be passed as-is to curl as a query parameter value.
    # Based on the HTML's `href` attribute, the value for `continue_url` parameter
    # (e.g., `https://www.aldi-sued.de`) is not URL-encoded (e.g., '/' does not become '%2F')
    # when submitted by a browser. Curl will handle the parameter as given.
    FULL_GRANT_URL="${GRANT_BASE_URL}${DYNAMIC_CONTINUE_URL}"
    log "Attempting to perform login by accessing: ${FULL_GRANT_URL}"

    # Perform a GET request to the grant URL.
    # We don't care about the response body, just that the request goes through successfully.
    # '-L' to follow any redirects, in case the grant URL immediately redirects to a success page.
    curl --interface "wan" -s -L -o /dev/null --max-time 15 "${FULL_GRANT_URL}"

    if [ $? -eq 0 ]; then
        log "Login request sent successfully to ${FULL_GRANT_URL}."
        return 0
    else
        log "Failed to send login request to ${FULL_GRANT_URL}. Curl exit code: $?."
        return 1
    fi
}

# --- Main script logic ---

# 1. Check if connected to the correct SSID
if ! is_connected_to_target_ssid; then
    log "Not connected to SSID '${SSID_TO_CHECK}'. Exiting."
    exit 0 # Exit quietly if not on the target network
fi

# 2. Check if internet access is already available
if check_internet_access; then
    log "Internet access already available. No login needed."
    exit 0
fi

# 3. Get the captive portal URL
PORTAL_URL=$(get_portal_url)
if [ $? -ne 0 ]; then
    log "Failed to get captive portal URL. Exiting."
    exit 1
fi
log "Detected Captive Portal URL: ${PORTAL_URL}"

# 4. Perform login
if perform_login "${PORTAL_URL}"; then
    log "Waiting a few seconds for network to stabilize after login attempt..."
    sleep 5 # Give some time for the portal to apply changes and network interfaces to update.
    if check_internet_access; then
        log "Successfully logged into ALDI SÜD gratis WLAN!"
        exit 0
    else
        log "Login attempt failed: Still no internet access after login request."
        exit 1
    fi
else
    log "Login attempt failed."
    exit 1
fi

# JSON_LIMITS: {"limit_type": "none", "limit_value": "none", "notes": "No explicit bandwidth or time limits found in the provided HTML or JavaScript."}
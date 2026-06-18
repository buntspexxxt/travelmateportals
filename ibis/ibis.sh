#!/bin/sh

# OpenWrt ash compatible shell script to automate login for ibis captive portal.

# Configuration
SSID="ibis"
TEST_URL="http://neverssl.com" # A reliable non-HTTPS URL for captive portal detection
USER_AGENT="Mozilla/5.0 (compatible; OpenWrt-CaptivePortal-Login/1.0; IbisHotel)"

# Helper function for logging messages to syslog and stdout
log() {
    logger -t "CaptivePortalLogin" "$@"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $@"
}

# Function to check if internet connectivity is available
check_internet() {
    log "Checking internet connectivity..."
    # Ping Google's public DNS server (8.8.8.8) with a single packet and a 3-second timeout
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log "Internet is accessible."
        return 0 # Internet is available
    else
        log "Internet is NOT accessible."
        return 1 # Internet is not available
    fi
}

# Function to get the currently connected Wi-Fi SSID
get_current_ssid() {
    local current_ssid=""
    # Iterate over all detected wireless interfaces to find the associated SSID
    for iface in $(iwinfo | grep "ESSID" | awk '{print $1}'); do
        # Use iwinfo to get details for each interface
        current_ssid=$(iwinfo "$iface" info 2>/dev/null | grep "ESSID" | awk -F': "' '{print $2}' | sed 's/"//g')
        # If an SSID is found and it's not "off/any" (meaning not connected or disabled)
        if [ -n "$current_ssid" ] && [ "$current_ssid" != "off/any" ]; then
            echo "$current_ssid"
            return 0 # Return the SSID and exit
        fi
    done
    echo "" # Return empty if no SSID is found on any interface
    return 1
}

# Function to attempt logging into the captive portal
login_portal() {
    log "Attempting to log in to the captive portal..."

    local initial_redirect_url=""
    # Use curl to send a HEAD request, follow redirects (-L), and dump headers (-D -).
    # We grep for 'Location:' headers, take the last one (which is the final redirect target),
    # extract the URL, and remove carriage returns.
    initial_redirect_url=$(curl -s -I -L "$TEST_URL" --user-agent "$USER_AGENT" 2>&1 | grep -i '^Location:' | tail -n 1 | awk '{print $2}' | tr -d '\r')

    if [ -z "$initial_redirect_url" ]; then
        log "Could not get an initial redirect URL. This might mean the portal is not active or we are already logged in."
        # As a fallback, try to check internet directly
        if check_internet; then
            log "Internet check confirmed. We are already logged in."
            return 0
        fi
        log "No redirect URL found and internet is not accessible. Cannot proceed with portal login without a target URL."
        return 1
    fi

    log "Initial redirect URL found: $initial_redirect_url"

    # Extract hostname and protocol from the redirect URL
    local portal_host=$(echo "$initial_redirect_url" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
    local portal_protocol=$(echo "$initial_redirect_url" | grep -o -E "^https?://")

    # Default to http if no protocol is explicitly found
    if [ -z "$portal_protocol" ]; then
        portal_protocol="http://"
    fi

    # The HTML's __sceneConfig JavaScript object provides a clue:
    # "scenePlayerUri":"\/sscp\/iGKzCQzLrzwyM4q1\/"
    # This path is a strong candidate for the base URL where the portal's main application logic resides.
    # We hypothesize that a "connect" or "login" action occurs relative to this base path.
    local scene_player_base="/sscp/iGKzCQzLrzwyM4q1"
    local login_post_url="${portal_protocol}${portal_host}${scene_player_base}/connect"

    log "Attempting POST to inferred login URL: $login_post_url"
    log "This script assumes a simple 'connect' action is triggered by POSTing to this endpoint."
    log "If this fails, manual inspection of the portal's network requests (e.g., using browser developer tools) is required to determine the exact POST URL and payload."

    local post_response=""
    local http_status=""

    # Attempt 1: Simple POST with no specific data.
    # This is common for "Accept Terms" or generic "Connect" buttons in captive portals,
    # where the server just needs to acknowledge the request.
    log "Attempt 1: POST to $login_post_url with empty data."
    post_response=$(curl -s -X POST "$login_post_url" \
        -H "User-Agent: $USER_AGENT" \
        -H "Accept: application/json, text/plain, */*" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -D -) # Dump response headers for debugging

    # Extract HTTP status code from the response headers
    http_status=$(echo "$post_response" | grep -i HTTP/ | head -n 1 | awk '{print $2}')
    log "Response HTTP Status: $http_status"

    # After the POST attempt, check if internet access has been granted
    if check_internet; then
        log "Successfully connected to ibis Wi-Fi using Attempt 1!"
        return 0
    fi

    # Attempt 2: If the first attempt fails, try with a common 'action=connect' parameter.
    # Some portals expect a specific parameter, even if its value is generic.
    log "Attempt 1 failed. Attempt 2: POST to $login_post_url with 'action=connect' data."
    post_response=$(curl -s -X POST "$login_post_url" \
        -H "User-Agent: $USER_AGENT" \
        -H "Accept: application/json, text/plain, */*" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data "action=connect" \
        -D -)

    http_status=$(echo "$post_response" | grep -i HTTP/ | head -n 1 | awk '{print $2}')
    log "Response HTTP Status: $http_status"

    if check_internet; then
        log "Successfully connected to ibis Wi-Fi using Attempt 2!"
        return 0
    fi

    log "Failed to log in to the captive portal after multiple attempts."
    log "Manual analysis is required to determine the exact POST URL and payload."
    return 1
}

# Main script logic starts here
log "Starting ibis Captive Portal Login Script (SSID: $SSID)"

# Check if 'curl' command is available, as it's essential for this script
if ! command -v curl >/dev/null 2>&1; then
    log "Error: 'curl' command not found. Please install it (e.g., 'opkg update; opkg install curl')."
    exit 1
fi

local current_ssid=""
# Check if 'iwinfo' command is available for accurate SSID detection
if ! command -v iwinfo >/dev/null 2>&1; then
    log "Warning: 'iwinfo' command not found. SSID detection might be inaccurate."
    log "Proceeding under the assumption that the device is manually connected to '$SSID'."
    current_ssid="$SSID" # If iwinfo is missing, assume connection to target SSID
else
    current_ssid=$(get_current_ssid)
fi

log "Current detected SSID: '$current_ssid'"

# Ensure the device is connected to the target SSID
if [ "$current_ssid" != "$SSID" ]; then
    log "Not connected to the target Wi-Fi network ('$SSID'). Please connect manually first. Exiting."
    exit 0
fi

# Check internet connectivity before attempting portal login
if check_internet; then
    log "Already connected to the internet. No action needed."
    exit 0
else
    log "Internet not accessible. Proceeding with captive portal login attempt."
    login_portal
    exit $? # Exit with the status code of the login_portal function
fi

# JSON_LIMITS: {"limit_type": "NONE", "limit_value": "N/A", "notes": "No explicit bandwidth or time limits mentioned in the provided HTML/JS or inferred from common portal behavior for ibis hotels."}
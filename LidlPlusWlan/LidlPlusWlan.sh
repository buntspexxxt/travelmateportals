#!/bin/sh

# This script automates login for the LidlPlusWlan captive portal on OpenWrt.
# It checks for connectivity to the target SSID, attempts to detect if a captive
# portal is active, and then performs a simulated login by sending a POST request.

# Configuration
SSID="LidlPlusWlan"
CONNECTIVITY_CHECK_URL="http://connectivity-check.ubuntu.com/"
# curl options:
# -s: Silent mode (don't show progress or error messages)
# -L: Follow redirects (used in perform_login to handle post-login redirects)
# --max-time: Max total time for the operation
# --connect-timeout: Max time for the connection phase
CURL_OPTS="-s -L --max-time 15 --connect-timeout 7"
# User-Agent header is sometimes required by portals to mimic a browser.
# Uncomment and customize if you encounter issues without it.
# USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
# CURL_OPTS="${CURL_OPTS} -A \"${USER_AGENT}\""

# The captive portal login form has no explicit 'action' attribute or input fields.
# The button uses 'onclick="document.FX.login()"'.
# A common pattern for such "click-to-accept" portals is a POST request to the
# initial portal URL with a simple 'accept=true' or 'agree=1' parameter.
# Based on the German button text "Akzeptieren und damit einverstanden"
# (Accept and agree), 'accept=true' is a reasonable guess for the POST data.
LOGIN_DATA="accept=true"

# Function to log messages to syslog and stdout
log() {
    logger -t "captive-portal-lidl" "$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@"
}

# Checks if the device is currently associated with the target SSID.
# Returns 0 if connected, 1 otherwise.
is_connected_to_ssid() {
    # Using jsonfilter to parse ubus output, which is generally more reliable for JSON.
    local current_ssid=$(ubus call network.wireless status 2>/dev/null | jsonfilter -e '@.*.ssid' | grep -m 1 "^${SSID}$")
    if [ -n "$current_ssid" ]; then
        log "Connected to target SSID: $SSID"
        return 0
    else
        log "Not connected to target SSID ($SSID). Current SSIDs: $(ubus call network.wireless status 2>/dev/null | jsonfilter -e '@.*.ssid' | tr '\n' ' ')"
        return 1
    fi
}

# Checks for internet access by trying to reach a known external URL.
# Returns 0 if internet access is confirmed, 1 otherwise.
# If a captive portal redirect is detected, it echoes the portal URL.
check_internet_access() {
    log "Checking internet access via $CONNECTIVITY_CHECK_URL ..."
    
    # Use curl HEAD request (-I) to get headers without downloading the full page.
    # Do NOT follow redirects at this stage (remove -L from CURL_OPTS),
    # so we can capture the initial Location header if a redirect occurs.
    local response_headers=$(curl ${CURL_OPTS% -L*} -I "$CONNECTIVITY_CHECK_URL" 2>/dev/null)
    local http_code=$(echo "$response_headers" | head -n 1 | awk '{print $2}')
    local portal_url=""

    # Check if we were redirected (HTTP 302 or 307) and if there's a Location header
    if [ "$http_code" = "302" ] || [ "$http_code" = "307" ]; then
        portal_url=$(echo "$response_headers" | grep -i "Location:" | head -n 1 | awk '{print $2}' | tr -d '\r')
        if [ -n "$portal_url" ]; then
            # Verify if it's the expected portal domain.
            # For LidlPlusWlan, the Matomo URL suggests 'hotspot.cloudwifi.de'.
            if echo "$portal_url" | grep -q 'hotspot.cloudwifi.de'; then
                log "Redirected to captive portal: $portal_url"
                echo "$portal_url"
                return 1 # Not logged in, portal detected
            else
                log "Redirected to an unexpected URL ($portal_url). Assuming internet access is available."
                echo ""
                return 0 # Unexpected redirect, treat as connected for now.
            fi
        else
            log "Redirect detected (HTTP $http_code) but no Location header found. Unexpected."
            echo ""
            return 1 # No clear portal URL, but not 200.
        fi
    elif [ "$http_code" = "200" ]; then
        log "Internet access confirmed (HTTP 200)."
        echo "" # No portal URL
        return 0
    else
        log "No internet access or unexpected HTTP status ($http_code). Assuming portal is active or network issue."
        echo ""
        return 1 # Not 200, so assume no internet.
    fi
}

# Performs the login action on the captive portal.
# Requires the portal_url as an argument.
# Returns 0 on successful login initiation, 1 on failure.
perform_login() {
    local portal_url="$1"
    if [ -z "$portal_url" ]; then
        log "Error: No portal URL provided for login."
        return 1
    fi

    log "Attempting to log in to captive portal at $portal_url"
    
    # Send a POST request with the LOGIN_DATA.
    # Use -L (from CURL_OPTS) to follow any redirects after the POST (e.g., to a success page).
    # -o /dev/null to discard the response body (we only care about the status code).
    # -w "%{http_code}" to print the final HTTP status code after all redirects.
    local login_final_http_code=$(curl $CURL_OPTS -X POST -d "$LOGIN_DATA" -o /dev/null -w "%{http_code}" "$portal_url" 2>/dev/null)

    if [ "$login_final_http_code" = "200" ] || [ "$login_final_http_code" = "302" ] || [ "$login_final_http_code" = "307" ]; then
        log "Login POST request sent successfully. Final HTTP status: $login_final_http_code."
        # A successful login often redirects or results in 200 on a landing page.
        # We'll re-check internet access to confirm actual connectivity.
        return 0
    else
        log "Login POST request failed or returned unexpected status: $login_final_http_code."
        return 1
    fi
}

# Main script execution loop
MAX_RETRIES=10
RETRY_DELAY=15 # seconds between login attempts

# First, check if we are on the correct Wi-Fi network.
if ! is_connected_to_ssid; then
    log "Not connected to the specified SSID. Exiting."
    exit 0 # Exit quietly if not on the target network
fi

# Loop to continuously check and attempt login if needed
for i in $(seq 1 $MAX_RETRIES); do
    log "Attempt $i/$MAX_RETRIES to establish internet access."
    PORTAL_URL=$(check_internet_access)
    CHECK_STATUS=$? # 0 if internet access, 1 if portal detected or no internet

    if [ "$CHECK_STATUS" = "0" ]; then
        log "Internet access confirmed. Already logged in or no portal detected."
        exit 0
    fi

    # If CHECK_STATUS is 1, it means either a portal was detected or no internet
    if [ -n "$PORTAL_URL" ]; then
        log "Captive portal detected at $PORTAL_URL. Attempting login..."
        if perform_login "$PORTAL_URL"; then
            log "Login initiated. Giving portal time to connect. Re-checking in 10 seconds..."
            sleep 10 # Give the portal some time to process and update network state
        else
            log "Login attempt failed. Retrying in $RETRY_DELAY seconds..."
            sleep "$RETRY_DELAY"
        fi
    else
        log "No identifiable portal URL detected, but no internet access. Retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    fi
done

log "Failed to log in to captive portal after $MAX_RETRIES attempts."
exit 1

# JSON_LIMITS: {"note": "No explicit bandwidth or time limits mentioned in the provided HTML/JS. The privacy policy mentions logging of data volumes, but not user-facing limits."}
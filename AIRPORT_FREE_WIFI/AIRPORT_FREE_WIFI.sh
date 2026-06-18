ash
#!/bin/sh

# OpenWrt ASH Captive Portal Login Script

# Configuration for the captive portal
TARGET_SSID="AIRPORT_FREE_WIFI"
# A reliable HTTP site for initial connectivity check.
# This URL will be redirected to the captive portal if not logged in.
CHECK_URL="http://neverssl.com"
# The data to send in the POST request to log in.
# This is derived from the hidden input field: <input type="hidden" name="login" value="oneclick"/>
LOGIN_DATA="login=oneclick"
# Tag for system logs
LOG_TAG="CaptivePortalLogin"
# Time in seconds between checks for connectivity and login attempts
RETRY_INTERVAL=60

# --- Logging Function ---
# Uses the OpenWrt 'logger' utility to send messages to syslog.
log() {
    logger -t "$LOG_TAG" "$1"
}

# --- Function to check if TARGET_SSID is currently connected ---
# This function queries the OpenWrt wireless status via ubus and jsonfilter
# to see if any active wireless interface is currently associated with the TARGET_SSID.
# Requires 'ubus' and 'jsonfilter' to be installed (standard on OpenWrt).
is_connected_to_target_ssid() {
    local ssids_output
    # Get all SSIDs currently reported by wireless interfaces.
    # jsonfilter outputs each SSID on a new line.
    ssids_output=$(ubus call network.wireless status 2>/dev/null | jsonfilter -e '@.*.ssid')

    # Check if the TARGET_SSID exists in the list of currently connected SSIDs.
    # Using 'grep -q' for quiet check and '^...$ ' for exact line match.
    echo "$ssids_output" | grep -q "^$TARGET_SSID$"
    return $? # grep returns 0 for match, 1 for no match
}

# --- Function to check general internet connectivity ---
# Attempts to ping a reliable external server (Google DNS) to determine if
# there is full internet access.
check_internet() {
    # -c 1: send 1 packet
    # -W 2: wait 2 seconds for response (timeout)
    # >/dev/null 2>&1: discard all output (stdout and stderr)
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1
}

# --- Main Logic Loop ---
# This loop runs indefinitely, performing checks and login attempts.
while true; do
    if is_connected_to_target_ssid; then
        log "Router is connected to the target SSID: $TARGET_SSID."

        if check_internet; then
            log "Internet access is already available. No login required."
        else
            log "Connected to $TARGET_SSID, but no internet access detected. Attempting captive portal login..."

            # Step 1: Discover the captive portal's effective URL.
            # When not logged in, requests to CHECK_URL will be redirected to the portal login page.
            # curl -s: silent mode, -L: follow redirects, -o /dev/null: discard response body
            # -w "%{url_effective}\n": print the final URL after redirects.
            EFFECTIVE_URL=$(curl -s -L -o /dev/null -w "%{url_effective}\n" "$CHECK_URL" 2>/dev/null)

            if [ -z "$EFFECTIVE_URL" ]; then
                log "Error: Failed to get effective URL from '$CHECK_URL'. This might indicate a network issue or the portal is unavailable."
            else
                log "Detected effective portal URL: $EFFECTIVE_URL"

                # Extract the hostname from the effective URL.
                # Example: "http://hotspot.koeln/landingPages/cp/..." -> "hotspot.koeln"
                LOGIN_HOST=$(echo "$EFFECTIVE_URL" | awk -F'/' '{print $3}')
                # Construct the full login URL based on the form action="/login" from the HTML.
                LOGIN_URL="http://${LOGIN_HOST}/login"

                if [ -z "$LOGIN_HOST" ]; then
                    log "Error: Failed to parse login host from the effective URL '$EFFECTIVE_URL'."
                else
                    log "Attempting to POST login data to $LOGIN_URL with parameters: '$LOGIN_DATA'"
                    # Perform the POST request to the captive portal login endpoint.
                    # -s: silent, -X POST: specify POST method, -d: send data as application/x-www-form-urlencoded
                    RESPONSE=$(curl -s -X POST -d "$LOGIN_DATA" "$LOGIN_URL")
                    # Note: The actual response content (e.g., success message or redirect) is ignored for simplicity,
                    # as we primarily check for internet access post-login.

                    # Step 3: Verify internet access after the login attempt.
                    if check_internet; then
                        log "Captive portal login successful for $TARGET_SSID. Internet access is now available."
                    else
                        log "Captive portal login attempt failed for $TARGET_SSID. Still no internet access. Response snippet: ${RESPONSE:0:100}..."
                    fi
                fi
            fi
        fi
    else
        log "Not connected to the target SSID '$TARGET_SSID'. Current connection status unknown or different SSID. Waiting..."
    fi

    # Wait for the defined interval before the next check.
    sleep "$RETRY_INTERVAL"
done

# JSON_LIMITS: {"limit_type": "TIME", "limit_value": 4, "limit_unit": "hours", "notes": "per login, repeated login possible"}
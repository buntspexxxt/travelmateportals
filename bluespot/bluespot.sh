#!/bin/sh

# Configuration
SSID="bluespot"
PORTAL_URL="https://portal.wificloud.network/bluespot-oneclick/login"
PING_HOST="8.8.8.8" # Google DNS for internet connectivity check

# Function to log messages to syslog and stdout
log() {
    logger -t "CaptivePortalLogin" "$@"
    echo "$(date '+%Y-%m-%d %H:%M:%S') CaptivePortalLogin: $@"
}

# Function to check for internet connectivity by pinging a reliable host
check_internet() {
    log "Checking internet connectivity to $PING_HOST..."
    # Ping once, wait 2 seconds for response, suppress output
    if ping -c 1 -W 2 "$PING_HOST" >/dev/null 2>&1; then
        return 0 # Success, internet is accessible
    else
        return 1 # Failure, internet is not accessible
    fi
}

# Function to wait for Wi-Fi connection to the specified SSID
wait_for_wifi() {
    log "Waiting for Wi-Fi connection to SSID: $SSID..."
    local attempts=0
    local max_attempts=30 # Max 30 attempts, with 5-second sleep each (total 2.5 minutes)

    while [ "$attempts" -lt "$max_attempts" ]; do
        local current_ssid=""
        local connected_iface=""

        # Iterate through possible wireless client interfaces (those in 'station' or 'client' mode)
        # Use iwinfo to list all interfaces, then filter for client mode
        for iface in $(iwinfo | grep "Mode: Client" | awk '{print $1}'); do
            # Extract ESSID from the interface info, handling potential errors if interface is down/not configured
            current_ssid=$(iwinfo "$iface" info 2>/dev/null | grep "ESSID:" | head -n 1 | awk -F'"' '{print $2}')
            
            # Check if the extracted SSID matches our target SSID
            if [ -n "$current_ssid" ] && [ "$current_ssid" = "$SSID" ]; then
                connected_iface="$iface"
                break # Found our SSID, exit inner loop
            fi
        done

        if [ -n "$connected_iface" ]; then
            log "Connected to Wi-Fi SSID: $current_ssid on interface $connected_iface."
            return 0 # Successfully connected
        fi

        attempts=$((attempts + 1))
        sleep 5
    done

    log "Failed to connect to Wi-Fi SSID: $SSID after $max_attempts attempts."
    return 1 # Failed to connect within the timeout
}

# --- Main Script Logic ---

# 1. Ensure we are connected to the target Wi-Fi network
if ! wait_for_wifi; then
    log "Exiting: Not connected to the required Wi-Fi network ($SSID)."
    exit 1
fi

# 2. Check current internet status
if check_internet; then
    log "Internet is already accessible. No captive portal detected or already logged in."
    exit 0
else
    log "Internet is not accessible. Attempting captive portal login..."

    # 3. Attempt to log in to the captive portal
    # Check for curl first, then wget, as curl offers better control for POST requests
    if command -v curl >/dev/null 2>&1; then
        log "Using curl to submit portal login request."
        # -s: Silent mode (don't show progress or error messages)
        # -L: Follow redirects (important if the portal redirects after POST)
        # -X POST: Specify POST method
        # --data "session=": Send the 'session=' payload
        # -o /dev/null: Discard output
        if curl -s -L -X POST --data "session=" "$PORTAL_URL" -o /dev/null; then
            log "Portal login POST request sent. Waiting a few seconds for network to stabilize..."
            sleep 5 # Give the network a moment to reconfigure after login

            # 4. Verify login success
            if check_internet; then
                log "Successfully logged in to captive portal."
                exit 0
            else
                log "Login attempt failed: Internet still not accessible after submitting portal data."
                exit 1
            fi
        else
            log "Curl command failed to execute the POST request."
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        log "Using wget to submit portal login request (curl not found)."
        # -q: Quiet mode (suppress output)
        # --post-data="session=": Send the 'session=' payload
        # -O /dev/null: Discard output (uppercase O)
        if wget -q --post-data="session=" "$PORTAL_URL" -O /dev/null; then
            log "Portal login POST request sent via wget. Waiting a few seconds for network to stabilize..."
            sleep 5 # Give the network a moment to reconfigure after login

            # 4. Verify login success
            if check_internet; then
                log "Successfully logged in to captive portal."
                exit 0
            else
                log "Login attempt failed: Internet still not accessible after submitting portal data."
                exit 1
            fi
        else
            log "Wget command failed to execute the POST request."
            exit 1
        fi
    else
        log "Error: Neither curl nor wget found. Cannot submit portal login request."
        exit 1
    fi
fi

# JSON_LIMITS: {"limit_type": "NONE"}
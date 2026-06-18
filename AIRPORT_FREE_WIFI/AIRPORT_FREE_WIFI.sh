#!/bin/sh

SSID_TARGET="AIRPORT_FREE_WIFI"
TEST_URL="http://connectivity-check.ubuntu.com/generate_204" # A URL that usually gives 204 or redirects
PING_TARGET="8.8.8.8"

log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") $@"
}

# Function to check internet connectivity
check_connectivity() {
    log "Checking internet connectivity by pinging $PING_TARGET..."
    if ping -c 1 -W 3 "$PING_TARGET" >/dev/null 2>&1; then
        log "Internet connection is active."
        return 0
    else
        log "No internet connection detected."
        return 1
    fi
}

# Function to get current SSID for a client (station) interface
get_current_ssid() {
    # Use ubus to get wireless status. Parse for "mode": "sta" and "ssid"
    ubus call network.wireless status 2>/dev/null | awk -F'"' '
        BEGIN {
            in_sta_block = 0;
            current_ssid = "";
        }
        /"mode": "sta"/ {
            in_sta_block = 1; # Found a station mode block
        }
        /"ssid": "/ {
            # This line might appear in other contexts too, so only capture if in a sta_block
            if (in_sta_block == 1) {
                current_ssid = $4;
                print current_ssid;
                exit; # Print the first found station SSID and exit awk
            }
        }
        /}/ {
            # End of an object, reset block flag
            in_sta_block = 0;
        }
    '
}


# Main script logic
log "Starting captive portal login script for $SSID_TARGET..."

CURRENT_SSID=$(get_current_ssid)
log "Current SSID: '$CURRENT_SSID'"

if [ -z "$CURRENT_SSID" ]; then
    log "Could not determine current SSID from client interface. Exiting."
    exit 1
fi

if [ "$CURRENT_SSID" != "$SSID_TARGET" ]; then
    log "Not connected to target SSID '$SSID_TARGET'. Connected to '$CURRENT_SSID'. Exiting."
    exit 0 # Exit silently if not on the target network
fi

if check_connectivity; then
    log "Already online. Exiting."
    exit 0
fi

log "Attempting to detect captive portal..."

# Try to get the redirect URL
# Use --max-redirect=0 to prevent wget from following the redirect
# Use -S to show server response headers (Location)
# Use -O /dev/null to discard content
REDIRECT_HEADERS=$(wget -q -S --max-redirect=0 "$TEST_URL" -O /dev/null 2>&1)
CAPTIVE_PORTAL_LOCATION=$(echo "$REDIRECT_HEADERS" | awk -F'Location: ' '/Location: / {print $2}' | tr -d '\r')

if [ -z "$CAPTIVE_PORTAL_LOCATION" ]; then
    log "No captive portal redirect found for $TEST_URL. This might mean the portal is already authenticated, or there is a deeper network issue. Exiting."
    exit 1
fi

log "Detected captive portal redirect URL: $CAPTIVE_PORTAL_LOCATION"

# Extract the base URL for the login POST request
# Example: http://hotspot.koeln/landingPages/cp/guqs6n9d/start?redirurl=...
# We need http://hotspot.koeln
CAPTIVE_PORTAL_BASE_URL=$(echo "$CAPTIVE_PORTAL_LOCATION" | awk -F'[/]' '{print $1"//"$3}')
LOGIN_URL="${CAPTIVE_PORTAL_BASE_URL}/login"

log "Extracted captive portal base URL: $CAPTIVE_PORTAL_BASE_URL"
log "Constructed login URL: $LOGIN_URL"

# Prepare POST data
# The HTML indicates a hidden input name="login" value="oneclick"
# The checkbox for terms acceptance has no 'name' attribute, implying it's handled client-side or not checked by the server.
POST_DATA="login=oneclick"
log "Sending POST request to $LOGIN_URL with data: '$POST_DATA'"

# Perform the POST request
# -nv for no verbose output, --no-check-certificate if needed (common on captive portals)
# -O /dev/null to discard output
# Use --post-data for POST requests
wget -nv --no-check-certificate --post-data "$POST_DATA" "$LOGIN_URL" -O /dev/null
STATUS=$?
if [ $STATUS -eq 0 ]; then
    log "POST request sent successfully. Waiting a moment for connection to establish."
    sleep 5 # Give it a few seconds to register the login
else
    log "Failed to send POST request to the captive portal (wget exit status: $STATUS)."
    exit 1
fi

# Re-check connectivity after attempting login
if check_connectivity; then
    log "Successfully logged into the captive portal!"
    exit 0
else
    log "Login attempt failed. Still no internet connection."
    exit 1
fi

# JSON_LIMITS: {"limit_type": "TIME", "limit_value": "4 hours", "comment": "The duration of use with the OneClick procedure is generally limited to four hours from the respective login (repeated login possible)."}
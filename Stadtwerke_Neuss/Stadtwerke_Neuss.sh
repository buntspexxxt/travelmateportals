#!/bin/sh

# OpenWrt ASH compatible script to automate login for "Stadtwerke Neuss" captive portal.

# --- Configuration ---
SSID="Stadtwerke Neuss"
# A common URL for captive portal detection.
# If the portal is active, accessing this URL typically results in a redirect to the login page.
CHECK_URL="http://www.msftconnecttest.com/connecttest.txt"
# A reliable public DNS server to check actual internet connectivity.
INTERNET_CHECK_HOST="8.8.8.8"
# Time to wait (in seconds) after a login attempt before re-checking internet connectivity.
SLEEP_TIME=5

# --- Functions ---

# Function to log messages to syslog and stdout
log() {
    logger -t "captive-portal-login" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check internet connectivity by pinging a known host
check_internet() {
    ping -c 1 -W 2 "$INTERNET_CHECK_HOST" >/dev/null 2>&1
    return $?
}

# --- Main Script Logic ---

log "Starting captive portal login script for SSID: '$SSID'."

# Find the wireless client interface that is currently associated.
CLIENT_IFACE=""
for iface in $(iwinfo | grep -E "ESSID" | awk '{print $1}'); do
    mode=$(iwinfo "$iface" info 2>/dev/null | grep "Mode:" | awk '{print $2}')
    if [ "$mode" = "Client" ]; then
        CLIENT_IFACE="$iface"
        break
    fi
done

if [ -z "$CLIENT_IFACE" ]; then
    log "No wireless client interface found in 'Client' mode. Exiting."
    exit 1
fi

current_ssid=$(iwinfo "$CLIENT_IFACE" assoclist 2>/dev/null | grep "SSID" | awk '{print $NF}')

if [ -z "$current_ssid" ]; then
    log "Wireless interface '$CLIENT_IFACE' is not associated. Exiting."
    exit 0
fi

if [ "$current_ssid" != "$SSID" ]; then
    log "Not connected to target SSID '$SSID'. Current SSID: '$current_ssid'. Exiting."
    exit 0
fi

log "Connected to '$SSID' on interface '$CLIENT_IFACE'."

# Check if internet is already accessible
if check_internet; then
    log "Internet is already accessible. No captive portal login needed."
    exit 0
fi

log "Internet not accessible. Captive portal detected. Attempting login..."

# Step 1: Fetch the initial redirect URL to get portal parameters.
# We use 'curl -k -s -I' to get headers only (allowing insecure SSL if needed),
# and 'Location:' header will contain the full URL to the captive portal login page with all required parameters.
log "Fetching redirect headers from '$CHECK_URL'..."
REDIRECT_HEADERS=$(curl -k -s -I "$CHECK_URL")
LOGIN_URL=$(echo "$REDIRECT_HEADERS" | grep -i "Location:" | head -n 1 | sed 's/Location: //i' | tr -d '\r\n ')

if [ -z "$LOGIN_URL" ]; then
    log "Failed to get initial redirect URL from 'Location:' header. " \
        "Is the captive portal active and redirecting as expected? Exiting."
    exit 1
fi

log "Detected portal redirect URL: $LOGIN_URL"

# Extract uamip (host), uamport, and the full query string from LOGIN_URL.
# This assumes the URL structure is http://<uamip>:<uamport>/path?query_string
UAM_IP=$(echo "$LOGIN_URL" | sed -e 's/^[^:]*:\/\///' -e 's/\/:.*//' -e 's/\?.*//' -e 's/:.*//')
UAM_PORT=$(echo "$LOGIN_URL" | sed -e 's/^[^:]*:\/\/[^:]*//' -e 's/\/.*//' -e 's/\?.*//' -e 's/://')
if [ -z "$UAM_PORT" ]; then UAM_PORT="80"; fi # Default to 80 if port not explicitly in URL

# Extract the query string (parameters after '?')
QUERY_STRING=$(echo "$LOGIN_URL" | sed -n 's/^[^?]*\?\([^#]*\).*$/\1/p')

# The HTML form action is "/auth/login.php".
# The POST request needs to be sent to this path appended to the portal's host and port,
# and crucially, the extracted query parameters must be part of the POST target URL.
LOGIN_FORM_ACTION="/auth/login.php"
POST_TARGET_URL="http://${UAM_IP}:${UAM_PORT}${LOGIN_FORM_ACTION}?${QUERY_STRING}"

# Construct POST data as identified from the HTML form:
# 'haveTerms=1' is a hidden input.
# 'termsOK=on' is for the checkbox 'Ich akzeptiere die Nutzungsbedingungen'.
# 'button=kostenlos einloggen' is for the submit button.
POST_DATA="haveTerms=1&termsOK=on&button=kostenlos+einloggen"

log "Submitting login form to: $POST_TARGET_URL"
log "With POST data: $POST_DATA"

# Step 2: Submit the login form using curl.
# -k: Allows insecure SSL connections (useful for self-signed portal certs, though here it's HTTP).
# -s: Silent mode, hides progress and error messages.
# -L: Follows HTTP redirects, important as the portal might redirect after successful login.
# -X POST: Explicitly sets the HTTP request method to POST.
# -d: Specifies the POST data.
login_response=$(curl -k -s -L -X POST -d "$POST_DATA" "$POST_TARGET_URL")

# Give some time for the network to settle and routing tables to update after the login attempt.
log "Login request sent. Waiting $SLEEP_TIME seconds for network to stabilize..."
sleep "$SLEEP_TIME"

# Step 3: Verify login by re-checking internet connectivity.
if check_internet; then
    log "Successfully logged in to '$SSID'. Internet is now accessible."
    exit 0
else
    log "Failed to log in. Internet still not accessible after login attempt."
    # For debugging, uncomment the next line to see a truncated response from the portal.
    # log "Last portal response (truncated): $(echo "$login_response" | head -c 200)..."
    exit 1
fi

# JSON_LIMITS: {"limit_type": "VOLUME", "limit_value": 100}
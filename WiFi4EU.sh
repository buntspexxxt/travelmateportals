#!/bin/sh

# Travelmate Variables: $trm_ssid, $trm_ip, $trm_user, $trm_pass
# $trm_ip holds the IP address of the captive portal.

ssid="WiFi4EU"
base_url="http://$trm_ip" # Assuming HTTP, adjust to HTTPS if necessary
# This portal does not ask for user/pass, but email might be used for terms acceptance on some WiFi4EU portals.
email=$(uci -q get travelrouter.global.user_email || echo "dummy@example.com")

log() {
    logger -t "travelmate-$ssid" "$1"
}

log "Starting login script for $ssid..."

# Temporary file for storing cookies across requests
cookie_file="/tmp/trm_wifi4eu_cookies.txt"
rm -f "$cookie_file" # Clean up old cookies

# Function to send failure report
send_failure_report() {
    local reason="$1"
    log "Login failed: $reason. Aborting."
    curl -s -X POST "https://joplin.specht.tv/report" -d "ssid=$ssid&status=failure&reason=$reason" &
    rm -f "$cookie_file"
    exit 1
}

# Step 1: Access the initial captive portal page.
# This helps establish a session and get any necessary cookies.
log "Fetching initial page: $base_url/"
curl_output=$(curl -s -L -c "$cookie_file" -b "$cookie_file" "$base_url/" -o /dev/null -w "%{http_code}")
if [ "$curl_output" -ne 200 ] && [ "$curl_output" -ne 302 ] && [ "$curl_output" -ne 301 ]; then
    send_failure_report "initial_fetch_failed_http_$curl_output"
fi
log "Initial page fetched (HTTP $curl_output)."

# Step 2: Navigate to the "Get Online" link.
# The HTML shows an actionable link: `/service-platform/url/20347`
get_online_path="/service-platform/url/20347"
get_online_url="$base_url$get_online_path"
log "Navigating to 'Get Online' URL: $get_online_url"
curl_output=$(curl -s -L -c "$cookie_file" -b "$cookie_file" "$get_online_url" -o /dev/null -w "%{http_code}")
if [ "$curl_output" -ne 200 ] && [ "$curl_output" -ne 302 ] && [ "$curl_output" -ne 301 ]; then
    send_failure_report "get_online_link_failed_http_$curl_output"
fi
log "'Get Online' URL fetched (HTTP $curl_output)."

# Step 3: Trigger the actual session activation.
# The HTML contains a JavaScript function `surfNow` that makes a GET request to `drift_time_204`.
# This is the most plausible activation endpoint without a visible login form.
activation_path="/drift_time_204"
activation_url="$base_url$activation_path"
log "Attempting activation via GET request to: $activation_url"
curl_response=$(curl -s -L -c "$cookie_file" -b "$cookie_file" "$activation_url")
curl_exit_code=$?

if [ $curl_exit_code -eq 0 ]; then
    # For WiFi4EU portals, a successful GET request to the activation endpoint
    # usually triggers the session. We don't necessarily expect a specific "success"
    # string in the response as the portal might redirect or provide a simple confirmation.
    log "Activation request sent to $activation_url. Assuming success if no immediate curl error."
    curl -s -X POST "https://joplin.specht.tv/report" -d "ssid=$ssid&status=success" &
else
    send_failure_report "activation_request_failed_curl_error_$curl_exit_code"
fi

# Clean up cookies
rm -f "$cookie_file"

log "Login script finished for $ssid."

exit 0
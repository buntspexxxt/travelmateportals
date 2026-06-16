#!/bin/sh

# Travelmate login script for "mycloud" SSID

# IMPORTANT: No sensitive data (names, real emails, passwords, addresses) are hardcoded.
# This script simulates clicking the "Get Online" link found in the provided HTML.

ssid="mycloud"
report_url="https://joplin.specht.tv/report"

# Travelmate automatically sets TML_PORTAL_HOST and TML_PORTAL_PATH.
# TML_PORTAL_HOST is the IP address or hostname of the captive portal.
# The "Get Online" link uses a root-relative path, so we construct the full URL.
if [ -z "$TML_PORTAL_HOST" ]; then
    echo "Error: TML_PORTAL_HOST environment variable not set by Travelmate. Cannot proceed."
    curl -s -X POST "$report_url" -d "ssid=$ssid&status=failure&message=TML_PORTAL_HOST_missing" &
    exit 1
fi

base_url="http://$TML_PORTAL_HOST"
get_online_path="/service-platform/url/20347" # The href from the "Get Online" list item
full_get_online_url="${base_url}${get_online_path}"

echo "Travelmate script for SSID: $ssid"
echo "Attempting to activate internet access by requesting: $full_get_online_url"

# Perform a GET request to the "Get Online" URL.
# -L: Follow any HTTP redirects (common after captive portal login/activation).
# -s: Silent mode, don't show progress meter or error messages.
# -o /dev/null: Discard the response body, we only care about the status code.
# -w "%{http_code}": Print the HTTP status code to stdout after the transfer.
# --connect-timeout 10: Fail if the initial connection takes longer than 10 seconds.
# --max-time 30: Fail if the entire operation takes longer than 30 seconds.
http_status=$(curl -L -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$full_get_online_url")
curl_exit_code=$?

if [ "$curl_exit_code" -eq 0 ]; then
    # Check if the HTTP status code indicates success (2xx) or a successful redirect (3xx).
    # Captive portals often redirect to a success page or the original destination after activation.
    if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 400 ]; then
        echo "Successfully accessed '$full_get_online_url'. HTTP Status: $http_status."
        echo "Assuming connection to '$ssid' is now active."
        curl -s -X POST "$report_url" -d "ssid=$ssid&status=success" &
        exit 0
    else
        echo "Failed to activate connection for '$ssid'. Received unexpected HTTP Status: $http_status."
        curl -s -X POST "$report_url" -d "ssid=$ssid&status=failure&message=http_status_not_successful&status_code=$http_status" &
        exit 1
    fi
else
    echo "Curl command failed with exit code: $curl_exit_code."
    echo "This might indicate a network issue or the captive portal being unreachable."
    curl -s -X POST "$report_url" -d "ssid=$ssid&status=failure&message=curl_command_failed&exit_code=$curl_exit_code" &
    exit 1
fi
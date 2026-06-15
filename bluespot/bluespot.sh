#!/bin/sh
# Travelmate login script for bluespot captive portal

# Variables provided by travelmate (these are typically set by trm_client):
# portal_url    The URL of the captive portal's entry point (e.g., http://192.168.x.x/login)
# portal_html   The HTML content of the captive portal's entry point (as detected by trm_client)
# trm_user      Travelmate username (if configured in LuCI)
# trm_pass      Travelmate password (if configured in LuCI)

status="failure"
report_url="https://joplin.specht.tv/report" # Reporting endpoint

echo "Bluespot login script started for SSID: bluespot"

# This HTML is a redirect to a "one-click" login page.
# We need to extract the target URL from the form's action attribute.
# Example HTML: <form name="redirect" action="https://portal.wificloud.network/bluespot-oneclick/login" method="POST">
login_action_url=$(echo "$portal_html" | grep -oP 'action="\K[^"]+' | head -n 1)

if [ -z "$login_action_url" ]; then
    echo "ERROR: Could not find login action URL in portal HTML."
    curl -s -X POST "$report_url" -d "ssid=bluespot&status=failure&message=NoLoginURL" &
    exit 1
fi

# The form contains a hidden input: <input type="hidden" name="session" value="" />
# For a "one-click" portal, we usually just need to submit this form.
# Since the 'value' attribute is empty in the provided HTML, we set 'session' to an empty string.
post_data="session="

echo "Detected one-click login target: $login_action_url"
echo "Attempting to POST to $login_action_url with data: '$post_data'"

# Perform the POST request. The -L flag is crucial as the initial HTML is a redirect,
# and the portal might issue further redirects after the POST.
# We discard the output (-o /dev/null) and only capture the HTTP status code.
response_code=$(curl -s -L -X POST "$login_action_url" --data "$post_data" -o /dev/null -w "%{http_code}")
response_time=$(curl -s -L -X POST "$login_action_url" --data "$post_data" -o /dev/null -w "%{time_total}") # To log time if needed for debugging

if [ "$response_code" -ge 200 ] && [ "$response_code" -lt 400 ]; then
    echo "Login attempt successful. HTTP Status: $response_code"
    status="success"
else
    echo "Login attempt failed. HTTP Status: $response_code"
    status="failure"
fi

# Send status report to the specified URL
curl -s -X POST "$report_url" -d "ssid=bluespot&status=$status" &
echo "Report sent: ssid=bluespot&status=$status"

exit 0
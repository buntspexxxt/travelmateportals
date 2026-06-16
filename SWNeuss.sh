#!/bin/sh

# SSID for reporting purposes
ssid_for_report="SWNeuss"

# Base URL for the Peplink captive portal login
portal_base_url="https://guest7.ic.peplink.com/cp/login"

# Travelmate variables (provided by Travelmate environment)
# IMPORTANT: These will be replaced by Travelmate at runtime
client_mac="${trm_mac}"      # MAC address of the client device (e.g., A6:BE:EA:6E:A6:2E)
client_ip="${trm_ip}"        # IP address of the client device (e.g., 10.200.8.167)
gateway_ip="${trm_gw}"       # Gateway IP of the captive portal (e.g., 192.168.50.1)
gateway_mac="${trm_gwmac}"   # Gateway MAC of the captive portal (e.g., A8:C0:EA:52:CA:60)
orig_url="${trm_url}"        # Original URL client tried to access (e.g., http://www.msftconnecttest.com/connecttest.txt)

# Hardcoded parameters extracted from the provided HTML/JavaScript
# These values appear to be static for this specific portal instance, not client-specific.
sn="2939-508B-F086"
# Note: The `ssid` parameter in the URL uses an internal ID, not the broadcast SSID "SWNeuss".
cp_ssid_id="~CP_KEY_KoqKCOTKsie-rX87wdb1qA" 
cp_id="~CP_KEY_KoqKCOTKsie-rX87wdb1qA"
cp_time="1781589990" # A fixed future timestamp
checksum="c199c627d11dfaf90c90af14a6dd17eeba6adc8e"
lang="en"            # From `currentLanguage = "en";` in JS

# Dummy email, as per instructions, though not used by this specific portal HTML
# This variable would be used if the portal had an email input field.
email=$(uci -q get travelrouter.global.user_email || echo "dummy@example.com")

# Generate a current timestamp for the '_' parameter (milliseconds since epoch)
current_timestamp_ms=$(date +%s%N | cut -b1-13)

# Construct the query string for the GET request
# This mimics the `makeResumeLoginCall` function in the HTML's JavaScript,
# which is triggered by the "Connect to Internet" button.
QUERY_STRING="_=""${current_timestamp_ms}""&resume=true&command=login&lang=""${lang}"""
QUERY_STRING="${QUERY_STRING}&sn=""${sn}""&ssid=""${cp_ssid_id}""&ip=""${client_ip}""&client_mac=""${client_mac}"""
QUERY_STRING="${QUERY_STRING}&host_ip=""${gateway_ip}""&host_mac=""${gateway_mac}""&name=&time=""${cp_time}"""
QUERY_STRING="${QUERY_STRING}&cp_id=""${cp_id}""&checksum=""${checksum}""&orig_url=""${orig_url}"""
# The 'browser' parameter is omitted as Travelmate doesn't easily provide it and it's often optional.

# Full login URL
LOGIN_URL="${portal_base_url}?${QUERY_STRING}"

echo "Attempting to connect to SSID: ${ssid_for_report}"
echo "Generated Login URL: ${LOGIN_URL}"

# Perform the GET request to the login URL
# -s: Silent mode, don't show progress meter or error messages
# -L: Follow redirects (important for captive portals)
# -o /dev/null: Discard response body
# -w "%{http_code}": Output only the HTTP status code
http_code=$(curl -s -L -o /dev/null -w "%{http_code}" "${LOGIN_URL}")

# Check the HTTP status code for success (2xx or 3xx range)
if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
    echo "Connection attempt successful (HTTP status: ${http_code})."
    # Send success report
    curl -s -X POST "https://joplin.specht.tv/report" -d "ssid=${ssid_for_report}&status=success" &
else
    echo "Connection attempt failed (HTTP status: ${http_code})."
    # Send failure report
    curl -s -X POST "https://joplin.specht.tv/report" -d "ssid=${ssid_for_report}&status=failure" &
fi
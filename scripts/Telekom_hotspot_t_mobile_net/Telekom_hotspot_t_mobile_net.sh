#!/bin/bash

# SSID: Telekom_hotspot_t_mobile_net
# This script attempts to interact with the Telekom HotSpot captive portal.
# WARNING: This portal relies heavily on client-side JavaScript (AngularJS/Angular 2+ with Native Federation).
# The actual login forms and API endpoints are loaded dynamically by JavaScript chunks (e.g., chunk-U25KGTYM.js)
# which were not provided in the input. Therefore, this script can only fetch the initial HTML page
# and cannot proceed with an automated login using curl alone. Further manual investigation of the dynamically
# loaded JS and network requests would be required to fully automate.

# --- Configuration Variables ---
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_JAR="/tmp/telekom_hotspot_cookies.txt"
TEMP_HTML_FILE="/tmp/telekom_hotspot_response.html"

# Function to perform a connectivity check
check_connectivity() {
    echo "Checking internet connectivity..."
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        echo "Connectivity check successful. Internet is accessible."
        exit 0
    else
        echo "Connectivity check failed. Internet is NOT accessible after attempting login."
        exit 1
    fi
}

# --- Step 1: Initial Portal Detection and Redirect --- 
echo "Step 1: Initiating portal detection and following redirects."
echo "Attempting to access a known non-HTTPS URL to trigger the captive portal redirect."

INITIAL_URL="http://detectportal.firefox.com/"

# Use curl to follow redirects, capture the final URL, and save cookies.
# -L: Follow redirects
# -s: Silent mode (don't show progress bar)
# -o: Output to file
# -D: Dump headers to stderr
# -c: Save cookies to file
# -b: Read cookies from file
# -w: Output variables after request, specifically %{url_effective} for the final URL

# Capture effective URL and HTTP response.
# The response is sent to TEMP_HTML_FILE for later parsing, headers to stderr for verbosity.

HTTP_STATUS=$(curl -L -s -o "${TEMP_HTML_FILE}" -D /dev/stderr -c "${COOKIE_JAR}" \
                   -A "${USER_AGENT}" -w "%{http_code}" "${INITIAL_URL}" 2>&1 \
                   | grep -oP '^Location: \K.*' | tail -n 1)

# The actual final URL will be the last 'Location' header that curl followed, or the initial URL if no redirect.
# We need to re-run curl with -v to get the effective URL on stdout, and then capture it.
echo "Fetching initial page to determine effective URL and HTTP status..."
FINAL_LANDING_URL=$(curl -L -s -o /dev/null -w "%{url_effective}" "${INITIAL_URL}" -A "${USER_AGENT}")

echo "HTTP Status Code of final redirect: $HTTP_STATUS"
echo "Final landing URL: ${FINAL_LANDING_URL}"

if [ -z "${FINAL_LANDING_URL}" ] || [ "${HTTP_STATUS}" -ne 200 ] ; then
    echo "Error: Failed to reach the captive portal landing page or received non-200 status."
    echo "Curl output might be in /dev/stderr (check logs above)."
    exit 1
fi

echo "Initial page fetched and cookies saved to ${COOKIE_JAR}."

# Extract base URL and query parameters from the final landing URL
BASE_DOMAIN=$(echo "${FINAL_LANDING_URL}" | awk -F'[/:]' '{print $4}')
PORTAL_PATH=$(echo "${FINAL_LANDING_URL}" | sed -E 's|^https?://[^/]+(/[^?#]*).*$|\1|')
QUERY_STRING=$(echo "${FINAL_LANDING_URL}" | grep -oP '\?.*')

# Remove leading '?' from QUERY_STRING if present for easier parsing
QUERY_STRING_PARAMS=""
if [[ "${QUERY_STRING}" == \?* ]]; then
    QUERY_STRING_PARAMS="${QUERY_STRING#?}"
fi

ORIG_URL=$(echo "${QUERY_STRING_PARAMS}" | grep -oP 'origurl=\K[^&]*')
TS_PARAM=$(echo "${QUERY_STRING_PARAMS}" | grep -oP 'ts=\K[^&]*')

echo "Extracted Base Domain: ${BASE_DOMAIN}"
echo "Extracted Portal Path: ${PORTAL_PATH}"
echo "Extracted origurl: ${ORIG_URL}"
echo "Extracted ts: ${TS_PARAM}"

if [ -z "${ORIG_URL}" ] || [ -z "${TS_PARAM}" ]; then
    echo "Warning: origurl or ts parameter not found in the landing URL. This might affect subsequent requests."
fi

# --- Step 2: Analyze the HTML content of the landing page ---
echo "Step 2: Analyzing the downloaded HTML content for login forms."

# The HTML content indicated a client-side rendered application (AngularJS/Angular 2+).
# It uses <hsp-ecom3-root> and dynamically loads JavaScript files.
# There is no static HTML form that can be directly interacted with via curl POST requests.
# The actual login logic (form fields, submission URL, required tokens) is hidden within the JavaScript bundles.

# Print a snippet of the HTML to confirm its content
echo "Displaying first 50 lines of the downloaded HTML (to ${TEMP_HTML_FILE}):"
head -n 50 "${TEMP_HTML_FILE}"

# --- Step 3: Attempting to find specific login fields (expected to fail) ---
echo "Step 3: Searching for hidden input fields or form elements for login."

LOGIN_FORM_PRESENT=$(grep -c '<form' "${TEMP_HTML_FILE}")
if [ "$LOGIN_FORM_PRESENT" -gt 0 ]; then
    echo "Found HTML forms in the initial page. Further manual inspection is needed."
    # Even if forms are found, if they are rendered by JS, direct curl interaction is complex.
else
    echo "No direct HTML forms found in the initial page. This confirms dynamic rendering by JavaScript."
fi

# --- Step 4: No direct login possible via curl due to complex JS rendering ---
echo "Step 4: Automated login cannot be performed directly with curl."
echo "The portal employs a modern JavaScript framework (AngularJS/Angular 2+).
The login forms and interaction logic are generated client-side and dynamically fetched via JavaScript bundles."
echo "To proceed, you would need to:"
echo "  1. Use a browser's developer tools to inspect network requests made by the JavaScript application."
echo "  2. Identify the specific API endpoint for login/authentication."
echo "  3. Determine the POST data (username, password, CSRF tokens, session IDs) required by that endpoint."
echo "  4. Reverse-engineer how these tokens/IDs are generated or retrieved by the client-side JavaScript."
echo "Without this information, a curl-based login script cannot be reliably created."

# Since automated login is not feasible with the given information, we will exit with a failure.

# --- Step 5: Final Connectivity Check ---
# This will likely fail as no login was performed.
echo "Step 5: Performing final connectivity check (expected to fail as no login was performed)."
check_connectivity

exit 1 # Indicate failure to log in.

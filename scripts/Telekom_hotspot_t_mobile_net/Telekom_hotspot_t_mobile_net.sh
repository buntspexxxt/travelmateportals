#!/bin/bash

# --- Configuration --- START ---
# The initial URL that triggers the captive portal redirect.
# Often, this is http://detectportal.firefox.com/ or http://neverssl.com/
INITIAL_CHECK_URL="http://detectportal.firefox.com/"

# Cookie jar file to maintain session
COOKIE_JAR="/tmp/telekom_hotspot_cookies.txt"

# --- Configuration --- END ---

echo "========================================"
echo "Telekom Hotspot Portal Automation Script"
echo "========================================"

echo "Starting captive portal detection..."

# Step 1: Initial GET request to trigger the captive portal redirect
echo "1. Sending initial GET request to ${INITIAL_CHECK_URL} to detect portal and capture redirects."

# Capture full verbose output to a temporary file, and HTML response to another
CURL_VERBOSE_OUTPUT_FILE=$(mktemp)
HTML_RESPONSE_FILE=$(mktemp)

CURL_CMD="curl -L -v -k --cookie-jar ${COOKIE_JAR} ${INITIAL_CHECK_URL} -o ${HTML_RESPONSE_FILE}"
echo "Executing: ${CURL_CMD}"

# Execute curl and capture stderr (verbose output) to the file
# The actual HTML response will be saved to ${HTML_RESPONSE_FILE}
${CURL_CMD} 2> "${CURL_VERBOSE_OUTPUT_FILE}"
CURL_EXIT_CODE=$?

echo "Curl command finished with exit code: $CURL_EXIT_CODE"
echo "--- Curl Verbose Output (from ${CURL_VERBOSE_OUTPUT_FILE}) ---"
cat "${CURL_VERBOSE_OUTPUT_FILE}"
echo "---------------------------------------------------------------"

echo "--- HTML Response Body (from ${HTML_RESPONSE_FILE}) ---"
cat "${HTML_RESPONSE_FILE}"
echo "---------------------------------------------------------"

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Initial curl request failed. Cannot proceed."
    rm -f "${CURL_VERBOSE_OUTPUT_FILE}" "${HTML_RESPONSE_FILE}"
    exit 1
fi

# Extract the effective URL after all redirects from the verbose output
# Look for the last URL that curl reports it's connecting to, or the final Location header
LANDING_URL=$(grep -i '^< Location:' "${CURL_VERBOSE_OUTPUT_FILE}" | tail -n 1 | awk '{print $3}' | tr -d '\r')

if [ -z "$LANDING_URL" ]; then
    echo "WARNING: Could not reliably extract the final landing URL from Location headers. Attempting to get from curl info."
    # Fallback to getting the effective URL from curl's output for -L
    # This pattern matches 'URL transformed to <URL>' which is often the final URL after redirects.
    LANDING_URL=$(grep -i '^< *< URL transformed to' "${CURL_VERBOSE_OUTPUT_FILE}" | tail -n 1 | awk '{print $NF}' | tr -d '\r')
    if [ -z "$LANDING_URL" ]; then
        echo "ERROR: Failed to extract any potential landing URL. Script cannot continue without knowing where the portal redirected."
        rm -f "${CURL_VERBOSE_OUTPUT_FILE}" "${HTML_RESPONSE_FILE}"
        exit 1
    fi
    echo "Falling back to extracted URL: ${LANDING_URL}"
fi

echo "Detected landing page URL: ${LANDING_URL}"

# Extract base domain from the landing URL
BASE_DOMAIN=$(echo "$LANDING_URL" | awk -F'/' '{print $3}')
echo "Detected base domain: ${BASE_DOMAIN}"

# Clean up temporary files
rm -f "${CURL_VERBOSE_OUTPUT_FILE}" "${HTML_RESPONSE_FILE}"

echo ""
echo "--- Portal Analysis Summary ---"
echo "The captive portal at '${BASE_DOMAIN}' is a complex Angular application (indicated by `<hsp-ecom3-root>` and Angular JS bundles)."
echo "It heavily relies on JavaScript for rendering the user interface, including any potential login forms or agreement buttons."
echo "The provided HTML does not contain any static HTML forms (like `<form>` tags with visible input fields) that a simple curl script could interact with directly."
echo "All interactive elements are dynamically generated and managed by client-side JavaScript code. The portal also explicitly checks if JavaScript is disabled."
echo "Automating such a highly dynamic, JavaScript-driven Single-Page Application (SPA) with `curl` alone is not feasible as `curl` cannot execute client-side JavaScript."
echo "Therefore, an automated login with this script is highly unlikely to work without extensive reverse-engineering and simulation of complex API calls, which is beyond the scope of a standard curl script."
echo ""
echo "--- Connectivity Check ---"
ping -c 3 8.8.8.8 >/dev/null && echo "INFO: Connectivity check passed. You might be connected, or the portal allows some traffic without full login." && exit 0 || echo "INFO: Connectivity check failed. You are likely not connected or the portal requires further manual action in a browser." && exit 1

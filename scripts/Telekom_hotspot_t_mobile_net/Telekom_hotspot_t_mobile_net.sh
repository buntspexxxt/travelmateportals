#!/bin/bash

# SSID: Telekom_hotspot_t_mobile_net

# --- Configuration Variables ---
# The cookie jar file to maintain session state.
COOKIE_JAR="/tmp/telekom_hotspot_cookies.txt"
# Temporary file to store HTTP headers for analysis.
HEADERS_FILE="/tmp/telekom_hotspot_headers.txt"
# Temporary file to store the initial portal page HTML.
PORTAL_HTML_FILE="/tmp/telekom_hotspot_portal.html"

# --- Logging Function ---
log() {
    echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $1" >&2
}

log "Starting Telekom HotSpot analysis script for SSID 'Telekom_hotspot_t_mobile_net'."
log "This script has 'red' confidence. The portal uses complex JavaScript and dynamic content, making automated login via simple cURL commands unlikely to succeed without specific API endpoint knowledge and token handling not discoverable from static HTML/JS analysis."

# Clean up previous temporary files if they exist
rm -f "${COOKIE_JAR}" "${HEADERS_FILE}" "${PORTAL_HTML_FILE}"
log "Cleaned up old temporary files: ${COOKIE_JAR}, ${HEADERS_FILE}, ${PORTAL_HTML_FILE}"

# 1. Initial Portal Detection and Redirect Following
log "Attempting to reach the captive portal using a common detection URL."
log "Performing initial cURL request to http://detectportal.firefox.com/ to trigger redirects and capture the final portal page."

# Use -L to follow redirects, -s for silent mode (no progress bar), -D to save headers, -c to save cookies, -o to save body.
# -w "%{{url_effective}}" prints the final URL after all redirects.
INITIAL_CURL_OUTPUT=$(curl -L -s -o "${PORTAL_HTML_FILE}" -D "${HEADERS_FILE}" --cookie-jar "${COOKIE_JAR}" "http://detectportal.firefox.com/" -w "%{url_effective}")

CURL_STATUS=$?
if [ "$CURL_STATUS" -ne 0 ]; then
    log_error "Initial cURL request failed with status: $CURL_STATUS. Exiting."
    echo "--- Headers File Content ---"
    cat "${HEADERS_FILE}"
    echo "--- HTML File Content ---"
    cat "${PORTAL_HTML_FILE}"
    exit 1
fi

FINAL_PORTAL_URL="$INITIAL_CURL_OUTPUT"
log "Initial cURL request completed. Final effective URL after redirects: ${FINAL_PORTAL_URL}"
log "HTTP Headers from initial requests saved to ${HEADERS_FILE}"
log "Response HTML saved to ${PORTAL_HTML_FILE}"
log "Cookies saved to ${COOKIE_JAR}"

# Check if the final URL indicates a successful redirect to the Telekom HotSpot portal.
if [[ "$FINAL_PORTAL_URL" != *"hotspot.t-mobile.net"* ]]; then
    log_error "The redirection did not lead to a Telekom HotSpot page. Actual URL: ${FINAL_PORTAL_URL}"
    log "Please inspect ${HEADERS_FILE} and ${PORTAL_HTML_FILE} for details."
    exit 1
fi

# Extract base domain from the final portal URL dynamically.
# Example: https://hotspot.t-mobile.net/TCOM/... -> hotspot.t-mobile.net
BASE_DOMAIN=$(echo "$FINAL_PORTAL_URL" | grep -oP '(?<=https?://)[^/]+')
if [ -z "$BASE_DOMAIN" ]; then
    log_error "Could not extract base domain from final URL: ${FINAL_PORTAL_URL}"
    exit 1
fi
log "Extracted base domain: ${BASE_DOMAIN}"

# Extract dynamic query string parameters (origurl, ts) from the final portal URL.
# These are typically passed through redirects, not directly for login form submission.
QUERY_STRING=$(echo "$FINAL_PORTAL_URL" | grep -o '?.*' | cut -c 2-)
if [ -n "$QUERY_STRING" ]; then
    log "Extracted query string parameters: ${QUERY_STRING}"
    # Attempt to URL decode origurl if present (example: %3A -> :, %2F -> /)
    ORIG_URL_ENCODED=$(echo "$QUERY_STRING" | sed -n 's/.*origurl=\([^&]*\).*/\1/p')
    if [ -n "$ORIG_URL_ENCODED" ]; then
        ORIG_URL=$(echo "$ORIG_URL_ENCODED" | sed 's/%25/%%/g' | sed 's/\%3A/:/g;s/\%2F/\//g;s/\%3F/?/g;s/\%3D/=/g;s/\%26/\&/g;s/\%3B/;/g;s/\%21/!/g;s/\%2A/*/g;s/\%27/'\''/g;s/\%28/(/g;s/\%29/)/g;s/\%20/ /g')
        log "origurl (decoded): ${ORIG_URL}"
    else
        log "origurl parameter not found."
    fi
    TS_VALUE=$(echo "$QUERY_STRING" | sed -n 's/.*ts=\([^&]*\).*/\1/p')
    if [ -n "$TS_VALUE" ]; then
        log "ts: ${TS_VALUE}"
    else
        log "ts parameter not found."
    fi
else
    log "No query string parameters found in the final URL."
fi

log "Analyzing the downloaded portal HTML for static login forms..."

# Reviewing the HTML: The page uses an `<hsp-ecom3-root viewMode="PREGEN"></hsp-ecom3-root>` component and loads several JavaScript bundles (`polyfills.js`, `scripts.js`, `main.js`).
# An inline script block (`<script type="text/javascript">`) initializes an Angular module (`angular.module('hotspotApp')`) and populates `window.sessionStorage` with configurations.
# The configuration `hotspotSettings: {customLogin: {"enabled":true,"configured":false}, ..., tab: {"showLoginTab":true, ...}}` confirms that login functionality is available.
# However, there are NO visible HTML `<form>` elements with traditional username/password input fields or simple 'accept terms' buttons in the initial static HTML.
# This indicates that the login interface is dynamically rendered by JavaScript, and login actions would likely involve AJAX calls to specific API endpoints with dynamic payloads and potentially CSRF tokens.

log_error "Automated login for this Telekom HotSpot portal using cURL is not feasible based on static HTML/JS analysis."
log_error "The portal is a JavaScript-driven Single Page Application (SPA). Direct interaction with forms or buttons using cURL is not possible as they are dynamically generated and handle complex API interactions."
log_error "Reverse-engineering the JavaScript to find the exact login API endpoints, required JSON/form data, and dynamic tokens (like CSRF) would be necessary, which is beyond the scope of a simple cURL script and static analysis."
log "Setting confidence to 'red' and exiting as direct cURL login is highly unlikely to work without browser automation or extensive manual reverse engineering."

# 2. Connectivity Check (after attempting portal bypass)
log "Attempting to verify external connectivity (ping 8.8.8.8) to check internet access."
ping -c 3 8.8.8.8 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    log "Connectivity check passed. Internet access confirmed (portal might have been bypassed manually, or is already open)."
    exit 0 # Exit with success if internet is already available (e.g., manual login or previous attempt worked)
else
    log_error "Connectivity check failed. Internet access not confirmed after attempting to reach the portal."
    exit 1 # Exit with failure if no internet access after portal attempt.
fi

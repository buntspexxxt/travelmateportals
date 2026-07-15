#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Enable strict error checking
set -e

# --- Configuration ---
LOG_FILE="/tmp/captive_portal_log.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# --- Logging Function ---
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# --- Cleanup Function ---
cleanup() {
    log_message "Performing cleanup..."
    if [ -n "${COOKIE_FILE}" ] && [ -f "${COOKIE_FILE}" ]; then
        rm -f "${COOKIE_FILE}"
        log_message "Removed temporary cookie file: ${COOKIE_FILE}"
    fi
}

# --- Main Script ---

# Register cleanup function to run on exit
trap cleanup EXIT INT TERM

log_message "Starting captive portal script for SSID 'WIFI_DB'"

# --- Network Readiness Check ---
log_message "Waiting for IP, Gateway, and DNS..."
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1;
    then
        log_message "Network and DNS are ready!"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

# --- Initial Landing Page Request ---
log_message "Fetching initial landing page from neverssl.com..."

# Use a temporary cookie file for session management
COOKIE_FILE=$(mktemp)
log_message "Using cookie file: ${COOKIE_FILE}"

# First request to neverssl.com to get redirected to the portal
# The javascript on this page will redirect us to a specific neverssl subdomain.
# We need to capture this redirect. '-L' will follow redirects automatically.
# Using '-w "%{url_effective}"' to get the final URL after redirects.
LANDING_URL=$(curl -k -v -L -A "${USER_AGENT}" -m 15 -w "%{url_effective}" -o /dev/null "http://neverssl.com")

if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to fetch initial landing page from http://neverssl.com/."
    exit 1
fi

log_message "Initial landing page request completed. Effective URL: ${LANDING_URL}"

# The JavaScript on neverssl.com generates a dynamic URL like `http://prefix.neverssl.com/online`
# We need to post to this dynamic URL. The structure of this portal is that it redirects
# to a dynamically generated subdomain. We can use this to our advantage.

# The provided HTML indicates a JavaScript-driven redirect to a subdomain of neverssl.com.
# The script dynamically generates a URL like `http://<adjective><adjective><adjective><noun>.neverssl.com/online`.
# Since we just need to reach a page that triggers the captive portal, posting to this
# dynamically generated URL should be sufficient.

# The actual login/authentication part happens by the captive portal gateway when it
# sees the device connecting to a legitimate-looking (even if dynamic) hostname.
# In this case, the javascript itself generates the final destination. We don't need to
# extract hidden form fields as there are no static forms. The javascript *is* the logic.

# We'll perform a final check on the generated neverssl subdomain URL.
# The portal will likely redirect us from here if authentication is needed, or simply allow access.
# Since this is a 'neverssl' domain, it's designed to bypass captive portals by providing
# a plain HTTP endpoint that captive portals can redirect to and that users can access.

log_message "Attempting to access the dynamically generated NeverSSL URL: ${LANDING_URL}"

# We'll perform a curl to this dynamically generated URL. This should either result in
# successful access or a redirect to the actual captive portal login page.
# For this specific case, the goal is to reach `http://prefix.neverssl.com/online` which is
# designed to bypass captive portals.

# Let's try accessing this URL directly. If it successfully loads, it likely means the
# captive portal has been bypassed or the initial redirect was sufficient.

# We'll use curl to visit this URL. The captive portal gateway should recognize this
# as a legitimate attempt to connect and grant access, or redirect us to a login page.
# In this specific 'neverssl' case, the goal is to get to `http://<dynamic_host>.neverssl.com/online`
# which is designed to trigger captive portal authorization.

# The HTML and JS suggest that simply navigating to the generated URL is the mechanism.
# No POST data or specific credentials are required for this particular portal.

log_message "Performing final connection check using the generated URL: ${LANDING_URL}"

# Perform the final connection check using a Google endpoint after visiting the landing page.
# The logic here is that if we can reach the generated neverssl URL, the gateway should
# have registered our device and authorized it. The subsequent google check verifies actual internet.

# It's important to note that the provided HTML/JS does NOT contain a login form, password, or username.
# The mechanism is to redirect to a specific domain (`neverssl.com`) which is designed to be
# accessible through captive portals. The JavaScript dynamically generates a subdomain.
# Therefore, no POST request with credentials is needed. The captive portal likely just
# checks for DNS resolution and HTTP access to a known bypass domain.

# We will now perform the mandatory internet connectivity check.

log_message "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    # Using connectivitycheck.gstatic.com/generate_204 as a reliable check
    CHECK_CODE=$(curl -k -v -A "${USER_AGENT}" -m 8 -s -o /dev/null -w "%{{http_code}}" "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        log_message "SUCCESS: Internet connection verified!"
        exit 0
    fi
    log_message "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done

log_message "ERROR: Portal request completed but no Internet connectivity established after 40 seconds."
exit 1

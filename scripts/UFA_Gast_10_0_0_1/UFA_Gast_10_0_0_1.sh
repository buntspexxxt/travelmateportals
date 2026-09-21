#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Define log file
LOG_FILE="/tmp/captive_portal.log"

# Function to log messages
log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Mandatory wait for network setup
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

# User agent for curl
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Temporary cookie file
COOKIE_FILE="/tmp/captive_portal_cookies.txt"
trap 'rm -f "${COOKIE_FILE:-}"' EXIT

# Step 1: Initial redirect to detect portal
log_message "Step 1: Performing initial redirect to detect portal..."

# Using detectportal.firefox.com to get the actual portal URL
REDIRECT_URL=$(curl -k -L -m 15 -A "$USER_AGENT" -o /dev/null -w '%{redirect_url}' http://detectportal.firefox.com/success.txt 2>&1 | sed "s/\r//g")

if [ -z "$REDIRECT_URL" ]; then
    log_message "ERROR: Failed to get redirect URL from detectportal.firefox.com."
    exit 1
fi

log_message "Received redirect URL: $REDIRECT_URL"

# Step 2: Accessing the actual portal page
log_message "Step 2: Accessing the actual portal page at $REDIRECT_URL..."

# Extracting necessary parameters from the redirect URL
# Example: http://10.0.0.1:8880/guest/s/default/?ap=fc:ec:da:19:9e:61&ec=... 

# Extracting query string parameters
QUERY_STRING=$(echo "$REDIRECT_URL" | grep -o '?.*' | cut -c 2-)

# The HTML content is minimal and seems to just load a JS bundle.
# The JS code seems to handle the actual login logic or redirects.
# We need to fetch the main JS file to see if it contains login endpoints or forms.

# Constructing URL for the JS file
# From HTML: src="../10.0.0.1+8880/guest/s/default/static/js/main.77ba67bd.js"
# The base URL is likely derived from the redirect URL's domain and port.

PORTAL_HOST=$(echo "$REDIRECT_URL" | awk -F/ '{print $3}')
JS_URL="http://$PORTAL_HOST/guest/s/default/static/js/main.77ba67bd.js"

log_message "Fetching JavaScript file from $JS_URL..."

JS_CONTENT=$(curl -k -m 15 -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$JS_URL" 2>&1)

if [ $? -ne 0 ] || [ -z "$JS_CONTENT" ]; then
    log_message "ERROR: Failed to fetch JavaScript file from $JS_URL."
    log_message "Curl output: $JS_CONTENT"
    exit 1
fi

log_message "Successfully fetched JavaScript content."

# Analysis of the JS: The JS code appears to be a React application. It doesn't directly expose login form data or API endpoints in a simple way that can be scraped. 
# It seems to dynamically render a portal root element. 
# Without further analysis or a specific API endpoint being obvious, it's hard to construct a direct POST request.

# Given the structure, it's highly probable that the actual login submission happens via a POST request initiated by the JavaScript after it's executed in a browser.
# This type of client-side rendering and logic makes it difficult to automate with `curl` alone.

# Based on the provided information, there's no obvious form to submit or API endpoint to call directly. The JS seems to handle the logic. This suggests a higher complexity.

# We will attempt a POST request to the base portal URL with the extracted parameters, as this is a common pattern for captive portals.
# The parameters from the redirect are likely crucial for the subsequent POST request.

log_message "Step 3: Attempting to submit login POST request to the portal..."

# Constructing POST data. We include the query parameters from the redirect.
# There are no explicit username/password fields visible in the HTML or JS snippets. 
# This suggests a simple 'Accept Terms' or 'Connect' button might be present on the rendered page.

# A common pattern is to POST the query parameters back to the portal.
POST_DATA="$QUERY_STRING"

LOGIN_URL="http://$PORTAL_HOST/guest/s/default/"

log_message "Sending POST request to $LOGIN_URL with data: $POST_DATA"

LOGIN_RESPONSE=$(curl -k -m 15 -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST -d "$POST_DATA" "$LOGIN_URL" 2>&1)

if [ $? -ne 0 ]; then
    log_message "ERROR: POST request to $LOGIN_URL failed."
    log_message "Curl output: $LOGIN_RESPONSE"
    # Even if the POST fails, we still proceed to the internet connectivity check.
    # Sometimes the portal updates its state even on a failed-looking response.
fi

log_message "POST request completed. Response (first 500 chars): ${LOGIN_RESPONSE:0:500}"

# Step 4: Verify real Internet connectivity
log_message "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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

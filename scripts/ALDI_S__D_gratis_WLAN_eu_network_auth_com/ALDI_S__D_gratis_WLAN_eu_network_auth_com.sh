#!/bin/bash

# Enable verbose logging for curl and script
set -ex

# --- Configuration Variables ---
COOKIE_JAR="/tmp/aldi_cookies.txt"

# --- Step 1: Initialize Logging and Cleanup ---
echo "--- Starting ALDI SÜD gratis WLAN login script ---"
echo "Cleaning up previous cookie jar (if any): $COOKIE_JAR"
rm -f "$COOKIE_JAR"

# --- Step 2: Probe for Initial Captive Portal Redirect URL ---
# The portal redirects a standard connectivity check URL to its login page.
# We use detectportal.firefox.com as a common probe.
echo "Probing for initial captive portal redirect URL using detectportal.firefox.com..."

# Capture the effective URL after all redirects
LANDING_URL=$(curl -s -o /dev/null -w "%{url_effective}" http://detectportal.firefox.com/)

if [ -z "$LANDING_URL" ]; then
  echo "ERROR: Failed to get initial landing URL. No redirect detected or network issue."
  exit 1
fi

echo "Initial landing URL identified: $LANDING_URL"

# --- Step 3: Extract Base Portal Path ---
# The JavaScript uses a base path for constructing the 'grant' URL.
# Example LANDING_URL: https://eu.network-auth.com/splash/bs-qtcsd.7.1097/?mac=...
# We need: https://eu.network-auth.com/splash/bs-qtcsd.7.1097
BASE_PORTAL_PATH=$(echo "$LANDING_URL" | sed -E 's/^(https?:\/\/[^/]+\/splash\/[^/]+\/[^/]+)\/?.*/\1/')

if [ -z "$BASE_PORTAL_PATH" ]; then
  echo "ERROR: Failed to extract base portal path from landing URL: $LANDING_URL"
  exit 1
fi

echo "Base portal path extracted: $BASE_PORTAL_PATH"

# --- Step 4: Simulate JavaScript XMLHttpRequest HEAD request ---
# The portal's 'Zum Internet fortfahren' button triggers a JavaScript function.
# This function makes a HEAD request to the current page (LANDING_URL).
# It expects a 'Continue-Url' header in the response, which contains the actual URL to redirect to after successful login.
echo "Performing HEAD request to $LANDING_URL to get 'Continue-Url' header..."

# Capture both headers and stderr output for verbose logging
HEAD_RESPONSE_FULL=$(curl -v -s -I -H "X-Requested-With: XMLHttpRequest" -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$LANDING_URL" 2>&1)
HEAD_STATUS_CODE=$(echo "$HEAD_RESPONSE_FULL" | head -n 1 | awk '{print $2}')

echo "HEAD Request Status Code: $HEAD_STATUS_CODE"
echo "HEAD Response Headers:"
echo "$HEAD_RESPONSE_FULL"

if [ "$HEAD_STATUS_CODE" -ne 200 ] && [ "$HEAD_STATUS_CODE" -ne 302 ]; then
  echo "ERROR: HEAD request failed or returned unexpected status code: $HEAD_STATUS_CODE"
  exit 1
fi

# Extract the 'Continue-Url' header value
EXTRACTED_CONTINUE_URL=$(echo "$HEAD_RESPONSE_FULL" | grep -i '^Continue-Url:' | sed -E 's/^Continue-Url: (.*)/\1/' | tr -d '\r')

if [ -z "$EXTRACTED_CONTINUE_URL" ]; then
  echo "ERROR: Failed to extract 'Continue-Url' header from HEAD response."
  exit 1
fi

echo "Extracted 'Continue-Url': $EXTRACTED_CONTINUE_URL"

# --- Step 5: Construct and Execute the Grant URL ---
# The JavaScript then constructs a 'grant' URL using the base path and the extracted 'Continue-Url'.
# This simulates clicking the 'Zum Internet fortfahren' button and completing the portal interaction.
GRANT_URL="${BASE_PORTAL_PATH}/grant?continue_url=${EXTRACTED_CONTINUE_URL}"

echo "Constructed Grant URL: $GRANT_URL"
echo "Making GET request to the Grant URL to finalize login..."

# Use -L to follow redirects, as the grant URL might redirect to the actual continue_url (e.g., success.txt).
LOGIN_RESPONSE=$(curl -v -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$GRANT_URL" 2>&1)
LOGIN_STATUS_CODE=$(echo "$LOGIN_RESPONSE" | grep '< HTTP/1.' | tail -n 1 | awk '{print $2}')

echo "Final Grant URL Request Status Code: $LOGIN_STATUS_CODE"
echo "Login Response (last part):"
echo "$LOGIN_RESPONSE" | tail -n 10 # Print last 10 lines of verbose output

if [ "$LOGIN_STATUS_CODE" -ge 200 ] && [ "$LOGIN_STATUS_CODE" -lt 400 ]; then
  echo "Login request appears to be successful (Status code: $LOGIN_STATUS_CODE)."
else
  echo "ERROR: Login request failed or returned an unexpected status code: $LOGIN_STATUS_CODE"
  exit 1
fi

# --- Step 6: Verify Internet Connectivity ---
echo "Verifying internet connectivity by pinging 8.8.8.8..."
if ping -c 3 8.8.8.8 >/dev/null; then
  echo "SUCCESS: Internet connectivity confirmed!"
  exit 0
else
  echo "FAILURE: Could not ping 8.8.8.8. Internet connection not established."
  exit 1
fi

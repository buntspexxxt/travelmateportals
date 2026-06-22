#!/bin/sh

COOKIE_JAR=$(mktemp)
INITIAL_PROBE_URL="http://detectportal.firefox.com/"

# Perform the initial probe and capture the final effective URL after all redirects
# This also stores any initial cookies in COOKIE_JAR
FINAL_EFFECTIVE_URL=$(curl -sL -c "$COOKIE_JAR" -w '%{url_effective}\n' -o /dev/null "$INITIAL_PROBE_URL")

# Extract scheme (e.g., https://) and base domain (e.g., service.thecloud.eu) from the effective URL
SCHEME=$(echo "$FINAL_EFFECTIVE_URL" | grep -oP '^\w+://')
BASE_DOMAIN=$(echo "$FINAL_EFFECTIVE_URL" | grep -oP '(?<=//)[^/]+')

# The HTML analysis shows a "Get Online" link pointing to /service-platform/url/20347.
# Construct this activation URL using the dynamically extracted scheme and base domain.
ACTIVATION_PATH="/service-platform/url/20347"
ACTIVATION_URL="${SCHEME}${BASE_DOMAIN}${ACTIVATION_PATH}"

# Access the "Get Online" URL to trigger the connection/activation,
# ensuring cookies are sent and updated.
curl -sL -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$ACTIVATION_URL" -o /dev/null

# Clean up the temporary cookie file
rm -f "$COOKIE_JAR"

# Check for internet connectivity
ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
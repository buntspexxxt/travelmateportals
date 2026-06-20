#!/bin/sh

COOKIE_JAR=$(mktemp)

INITIAL_URL="http://detectportal.firefox.com/"

# Step 1: Get the initial redirect URL with dst parameter and store cookies
FIRST_REDIRECT_URL_HEADERS=$(curl -s -D - "$INITIAL_URL" -o /dev/null -c "$COOKIE_JAR")
FIRST_REDIRECT_LOCATION=$(echo "$FIRST_REDIRECT_URL_HEADERS" | grep -i "Location:" | head -n 1 | awk '{print $2}' | tr -d '\r\n')
DST_QUERY_STRING=$(echo "$FIRST_REDIRECT_LOCATION" | grep -o 'dst=[^&]*')

# Step 2: Get the final landing page URL and update cookies
LANDING_URL_HEADERS=$(curl -sL -D - "$INITIAL_URL" -o /dev/null -c "$COOKIE_JAR" -b "$COOKIE_JAR")
LANDING_URL=$(echo "$LANDING_URL_HEADERS" | grep -i "Location:" | awk '{print $2}' | tail -n 1 | tr -d '\r\n')

BASE_DOMAIN=$(echo "$LANDING_URL" | cut -d'/' -f3)
PORTAL_PATH=$(echo "$LANDING_URL" | cut -d'/' -f4- | cut -d'?' -f1)

# Step 3: Construct the login endpoint and POST data
# Assuming the login POST is to the base portal URL itself.
LOGIN_ENDPOINT="https://${BASE_DOMAIN}/${PORTAL_PATH}"

# Common Ucopia login for free WiFi often involves empty credentials and accepting terms.
# 'logonForm_connect_button=Connect' is the submit button value.
# 'private_policy_accept=on' is a common guess for a mandatory policy checkbox.
POST_DATA="login=&password=&${DST_QUERY_STRING}&logonForm_connect_button=Connect&private_policy_accept=on"

# Step 4: Perform the POST request to log in
curl -sL -X POST \
    -b "$COOKIE_JAR" \
    -c "$COOKIE_JAR" \
    -d "$POST_DATA" \
    "$LOGIN_ENDPOINT" -o /dev/null

check_quota() {
    # Ucopia portals often expose API endpoints for status/usage, e.g., /portal/api/status
    QUOTA_URL="https://${BASE_DOMAIN}/${PORTAL_PATH}api/status"
    curl -s -b "$COOKIE_JAR" "$QUOTA_URL"
}

# Step 5: Clean up cookie jar
rm -f "$COOKIE_JAR"

# Step 6: Connectivity check
ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
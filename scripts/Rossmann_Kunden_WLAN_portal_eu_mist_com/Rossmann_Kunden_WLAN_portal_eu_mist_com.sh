#!/bin/sh

COOKIE_JAR=$(mktemp)

# Step 1: Get the effective landing URL after redirects and download the HTML content
LANDING_URL=$(curl -s -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -o /dev/null -w "%{url_effective}" "http://detectportal.firefox.com/")
HTML_CONTENT=$(curl -s -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$LANDING_URL")

# Step 2: Extract dynamic hidden input values from the HTML content of the 'singleAuthForm'
AP_MAC=$(echo "$HTML_CONTENT" | grep -oP 'form[^>]*id="singleAuthForm"[^>]*>.*?input type="hidden" name="ap_mac" value="\K[^"]+' | head -n 1)
CLIENT_MAC=$(echo "$HTML_CONTENT" | grep -oP 'form[^>]*id="singleAuthForm"[^>]*>.*?input type="hidden" name="client_mac" value="\K[^"]+' | head -n 1)
WLAN_ID=$(echo "$HTML_CONTENT" | grep -oP 'form[^>]*id="singleAuthForm"[^>]*>.*?input type="hidden" name="wlan_id" value="\K[^"]+' | head -n 1)
REDIRECT_URL=$(echo "$HTML_CONTENT" | grep -oP 'form[^>]*id="singleAuthForm"[^>]*>.*?input type="hidden" name="url" value="\K[^"]+' | head -n 1)

# Step 3: Construct the POST data payload
# The 'singleAuthForm' is the initially visible form. It requires accepting 'tos' and submits with 'auth_method=passphrase'.
# The hidden fields ap_mac, client_mac, wlan_id, and url are also included in the POST body as per the form structure.
POST_DATA="ap_mac=$AP_MAC&client_mac=$CLIENT_MAC&wlan_id=$WLAN_ID&url=$REDIRECT_URL&tos=true&auth_method=passphrase"

# Step 4: Submit the login request to the LANDING_URL (which is the form's action URL)
curl -s -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST -d "$POST_DATA" "$LANDING_URL" -o /dev/null

# Step 5: Clean up cookie file
rm -f "$COOKIE_JAR"

# Step 6: Perform a connectivity check
ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
#!/bin/bash

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/wifi_cookies.txt"

echo "Starting automated login for bluespot_portal_wificloud_network"

# 1. Capture the initial redirect parameters to determine current location and session state
echo "Fetching initial portal landing page to extract parameters..."
INITIAL_RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" "http://portal.wificloud.network/?requestpage=loginpage&mac=a2:9e:e2:26:e6:a6&location=L3346&redirect=http:%2F%2Fdetectportal.firefox.com%2Fsuccess.txt&ssid=&nasport=WLC-TUNNEL-1")

echo "Extracting hidden form fields from HTML..."
# Parsing session ID or hidden inputs if they exist, though the redirect suggests a simple POST trigger
SESSION_VAL=$(echo "$INITIAL_RESPONSE" | grep -o 'name="session" value="[^"]*"' | cut -d'"' -f4)

echo "Submitting one-click login form..."
# The HTML indicates a POST to /bluespot-oneclick/login
POST_RESULT=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -d "session=$SESSION_VAL" \
  "https://portal.wificloud.network/bluespot-oneclick/login")

echo "HTTP Response from login attempt: $POST_RESULT"

# Connectivity check
echo "Verifying internet connectivity..."
ping -c 3 8.8.8.8 >/dev/null
if [ $? -eq 0 ]; then
  echo "Login successful: Internet is reachable."
  exit 0
else
  echo "Login failed: Internet is not reachable."
  exit 1
fi
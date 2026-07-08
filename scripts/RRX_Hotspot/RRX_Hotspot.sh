#!/bin/bash
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE="/tmp/portal_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX_Hotspot automation..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Accessing the initial portal trigger..." | tee -a "$LOG_FILE"
curl -k -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://neverssl.com" > /tmp/portal_page.html 2>&1

echo "Following redirect to hotspot provider (https://www.hotspots.de)..." | tee -a "$LOG_FILE"
# We use -L to follow redirects and store the final landing page
curl -k -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L "https://www.hotspots.de" > /tmp/login_page.html 2>&1

echo "Searching for form buttons to click..." | tee -a "$LOG_FILE"
# Extracting potential POST action or form details if needed, but per instructions, just clicking the button is sufficient.
# Often these portals have a form with a simple submit button.
FORM_ACTION=$(sed -n 's/.*<form action="\([^"]*\)".*/\1/p' /tmp/login_page.html | head -n 1)

if [ -z "$FORM_ACTION" ]; then
    echo "No form found, assuming direct link redirect or simple GET trigger..." | tee -a "$LOG_FILE"
else
    echo "Submitting form to $FORM_ACTION..." | tee -a "$LOG_FILE"
    # Per instructions, no checkboxes needed, just a trigger.
    # Using POST to the action URL identified.
    curl -k -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -d "submit=1" "$FORM_ACTION" > /tmp/final_auth.html 2>&1
fi

echo "Final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && { echo "Internet access successful!"; exit 0; } || { echo "No internet access."; exit 1; }
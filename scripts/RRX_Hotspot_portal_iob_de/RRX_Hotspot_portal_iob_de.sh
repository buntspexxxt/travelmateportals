#!/bin/bash
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Login Process..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

perform_curl() {
    curl -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$@"
}

echo "Step 1: Accessing initial redirect to capture Hotsplots parameters..." | tee -a "$LOG_FILE"
# Use a common captive portal detection URL. neverssl.com is suitable.
INITIAL_REDIRECT_RESPONSE=$(perform_curl "http://neverssl.com" 2>&1)
REDIRECT_URL=$(echo "$INITIAL_REDIRECT_RESPONSE" | grep "Location:" | sed 's/Location: //g' | sed 's/\r//g' | tail -n 1)

if [ -z "$REDIRECT_URL" ]; then
    echo "ERROR: Initial redirect URL not found. Exiting." | tee -a "$LOG_FILE"
    echo "Full curl -k output:" | tee -a "$LOG_FILE"
    echo "$INITIAL_REDIRECT_RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi
echo "Initial Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

# Extract the Hotsplots login URL from the portal.iob.de redirect
LOGIN_URL=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\([^&]*\).*/\1/p' | sed 's/%3a/:/g;s/%2f/\//g;s/%26/\&/g;s/%3d/=/g')

if [ -z "$LOGIN_URL" ]; then
    echo "ERROR: Hotsplots LOGIN_URL not found in redirect. Exiting." | tee -a "$LOG_FILE"
    echo "Redirect URL content: $REDIRECT_URL" | tee -a "$LOG_FILE"
    exit 1
fi
echo "Hotsplots Login URL: $LOGIN_URL" | tee -a "$LOG_FILE"

echo "Step 2: Accessing Hotsplots login page to extract form details..." | tee -a "$LOG_FILE"
HOTSPOTS_LOGIN_PAGE_HTML=$(perform_curl "$LOGIN_URL" 2>&1)

echo "Extracting form parameters from Hotsplots login page..." | tee -a "$LOG_FILE"
# The form action is likely the base URL of LOGIN_URL
FORM_ACTION=$(echo "$LOGIN_URL" | cut -d'?' -f1) # This should be something like https://www.hotsplots.de/auth/login.php

CHALLENGE=$(echo "$HOTSPOTS_LOGIN_PAGE_HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HOTSPOTS_LOGIN_PAGE_HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HOTSPOTS_LOGIN_PAGE_HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
MAC=$(echo "$HOTSPOTS_LOGIN_PAGE_HTML" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$HOTSPOTS_LOGIN_PAGE_HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

if [ -z "$CHALLENGE" ] || [ -z "$UAMIP" ] || [ -z "$UAMPORT" ] || [ -z "$MAC" ] || [ -z "$NASID" ]; then
    echo "ERROR: One or more Hotsplots form parameters missing. Exiting." | tee -a "$LOG_FILE"
    echo "Hotsplots login page HTML:" | tee -a "$LOG_FILE"
    echo "$HOTSPOTS_LOGIN_PAGE_HTML" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracted Hotsplots parameters: Challenge=$CHALLENGE, UAMIP=$UAMIP, UAMPORT=$UAMPORT, MAC=$MAC, NASID=$NASID" | tee -a "$LOG_FILE"

echo "Step 3: Submitting Hotsplots login form with empty credentials (assuming free access)..." | tee -a "$LOG_FILE"
POST_DATA="username=&password=&button=Login&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&nasid=$NASID"

# The curl command here uses -L to capture the final HTML after redirects from Hotsplots.
# This HTML is expected to be the "RRX Startseite" as provided in the problem description.
POST_LOGIN_HTML=$(perform_curl -X POST -d "$POST_DATA" "$FORM_ACTION" 2>&1)

# Basic check for common error patterns, this might need refinement based on actual portal behavior
if echo "$POST_LOGIN_HTML" | grep -qE "(error|failure|failed)" ; then
    echo "WARNING: Hotsplots POST response HTML potentially indicates an error or unexpected content." | tee -a "$LOG_FILE"
    # echo "$POST_LOGIN_HTML" | tee -a "$LOG_FILE" # Uncomment for detailed debugging if issues persist
fi

echo "Step 4: Hotsplots login submitted. Now checking for the 'Online gehen' button on the landing page..." | tee -a "$LOG_FILE"
# Extract the 'Online gehen' link from the POST_LOGIN_HTML (which is the RRX Startseite)
PRELOGIN_URL=$(echo "$POST_LOGIN_HTML" | sed -n 's/.*<a href="\([^"]*\)" class="btn btn-primary btn-lg">Online gehen<\/a>.*/\1/p')

if [ -z "$PRELOGIN_URL" ]; then
    echo "ERROR: 'Online gehen' URL not found on the landing page after Hotsplots login. Exiting." | tee -a "$LOG_FILE"
    echo "Full HTML after Hotsplots POST (where 'Online gehen' was expected):" | tee -a "$LOG_FILE"
    echo "$POST_LOGIN_HTML" | tee -a "$LOG_FILE"
    exit 1
fi
echo "'Online gehen' URL found: $PRELOGIN_URL" | tee -a "$LOG_FILE"

echo "Step 5: Clicking 'Online gehen' button to finalize the connection..." | tee -a "$LOG_FILE"
FINAL_ACTIVATION_RESPONSE=$(perform_curl "$PRELOGIN_URL" 2>&1)

# Log a snippet of the final activation response for debugging
echo "Final activation request completed. Response snippet (last 10 lines):" | tee -a "$LOG_FILE"
echo "$FINAL_ACTIVATION_RESPONSE" | tail -n 10 | tee -a "$LOG_FILE"


echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{\http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
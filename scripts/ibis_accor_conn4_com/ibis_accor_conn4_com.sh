#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting captive portal login script for SSID: ibis_accor_conn4_com"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Checking if already logged in by accessing a known secure site..."
# Use curl to check if we are already authenticated by trying to access a site that would typically redirect if not logged in.
# A common pattern is that authenticated users get a 302 redirect to '/', while unauthenticated users get redirected to the portal.
# We'll try to get to accor.conn4.com directly and see if it redirects to itself or the portal.
LOGIN_CHECK_URL="https://accor.conn4.com/"
EFFECTIVE_URL=$(curl -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -v -L -c /tmp/cookies.txt -b /tmp/cookies.txt --connect-timeout 5 --max-time 10 "$LOGIN_CHECK_URL" 2>&1 | grep -i 'Location:' | sed -n 's/.*Location: //p' | tr -d '\r')

echo "Initial check - Effective URL after accessing $LOGIN_CHECK_URL: $EFFECTIVE_URL"

if [[ "$EFFECTIVE_URL" == "$LOGIN_CHECK_URL" || "$EFFECTIVE_URL" == "${LOGIN_CHECK_URL}" ]]; then
    echo "Already logged in or no portal detected. Exiting successfully." | tee -a "$LOG_FILE"
    exit 0
fi

PORTAL_URL="https://accor.conn4.com/"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIES_FILE="/tmp/portal_cookies.txt"

echo "Fetching the initial portal page: $PORTAL_URL"

# Fetch the initial portal page to get any necessary cookies or hidden form fields.
PORTAL_RESPONSE=$(curl -A "$USER_AGENT" -v -L -c "$COOKIES_FILE" -b "$COOKIES_FILE" --connect-timeout 10 --max-time 20 "$PORTAL_URL")
CURL_EXIT_CODE=$?

echo "Curl command for initial portal fetch exited with code: $CURL_EXIT_CODE"
# echo "Portal Response (first 500 chars): ${PORTAL_RESPONSE:0:500}" # Optional: for debugging

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to fetch the initial portal page from $PORTAL_URL. Curl exit code: $CURL_EXIT_CODE." | tee -a "$LOG_FILE"
    exit 1
fi

# The HTML indicates that the portal is built with Vue.js and uses configuration from __sceneConfig.
# The main script loaded is /static-assets/accor/i-accor/assets/index-DIUbTxKq.js.
# The otSDKStub.js also loads and likely handles cookie consent, which is common.
# Since there's no obvious login form with username/password fields in the initial HTML, it's likely a simple click-to-connect or terms acceptance.
# The JS code loaded is quite extensive, suggesting complex client-side logic. However, there's no visible CAPTCHA or complex input requirement.
# The previous logs show redirects: firefox.com -> accor.conn4.com/ident -> accor.conn4.com/
# The success.txt file is saved, meaning the initial detection worked. The final response is 200 OK to /. 
# This suggests that after the initial detection, the user might already be considered logged in or the subsequent steps are handled by JS.

# Given the complexity of the JS and the nature of modern portals, a direct POST might not be sufficient.
# However, the HTML does not present a form to submit. The __sceneConfig object contains 'redirectUrl' and 'redirectInterval'.
# The JS is loading a lot of assets and potentially initializes the connection.

# Let's try to mimic the subsequent JS calls if possible, or rely on the fact that a successful detection redirects to '/' which implies a connection.
# The provided code is mostly client-side setup. A common pattern for such portals is that after the initial HTML is served,
# further requests or JS execution might lead to a successful connection.

# Based on the logs, the detection by firefox.com leads to a redirect to accor.conn4.com/ident which then redirects to https://accor.conn4.com/.
# The fact that `success.txt` was served suggests the portal logic might have already been satisfied or is handled by the loaded JS.

# Let's try to re-request the root URL again, ensuring cookies are used, to see if it triggers a final connection.

echo "Attempting to access the root URL again with cookies to finalize connection..."
FINAL_CHECK_URL="https://accor.conn4.com/"
FINAL_RESPONSE=$(curl -A "$USER_AGENT" -v -L -c "$COOKIES_FILE" -b "$COOKIES_FILE" --connect-timeout 10 --max-time 20 "$FINAL_CHECK_URL")
FINAL_EXIT_CODE=$?

echo "Curl command for final check exited with code: $FINAL_EXIT_CODE"

if [ $FINAL_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to perform final check on $FINAL_CHECK_URL. Curl exit code: $FINAL_EXIT_CODE." | tee -a "$LOG_FILE"
    exit 1
fi

# Now, perform a connectivity check to ensure we have internet access.
echo "Performing internet connectivity check..."
ping -c 3 8.8.8.8 >/dev/null
PING_EXIT_CODE=$?

if [ $PING_EXIT_CODE -eq 0 ]; then
    echo "Internet connectivity confirmed. Portal login successful." | tee -a "$LOG_FILE"
    exit 0
else
    echo "Error: Internet connectivity check failed. Could not connect to 8.8.8.8." | tee -a "$LOG_FILE"
    exit 1
fi

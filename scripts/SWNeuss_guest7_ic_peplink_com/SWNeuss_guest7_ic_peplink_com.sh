#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Define log file
LOG_FILE="/tmp/portal_login.log"

# Cleanup function
cleanup() {
    echo "Cleaning up temporary files..." >> "$LOG_FILE"
    rm -f "$COOKIE_FILE"
    rm -rf "/tmp/portal_tmp_$$"
}

# Trap EXIT signal to ensure cleanup
trap cleanup EXIT

# Initialize log file
echo "Starting captive portal script for SSID 'SWNeuss_guest7_ic_peplink_com'" > "$LOG_FILE"

# Wait for network connectivity
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1;
    then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

# Create a temporary directory for downloaded files
PORTAL_TMP_DIR="/tmp/portal_tmp_$$"
mkdir -p "$PORTAL_TMP_DIR/portal"

# Create a temporary cookie file
COOKIE_FILE="$PORTAL_TMP_DIR/cookies.txt"
echo "Created temporary cookie file: $COOKIE_FILE" >> "$LOG_FILE"

# --- Step 1: Initial Redirect --- 
# The first step is to visit the initial redirect URL to get the captive portal page.
# This often happens automatically when a browser detects a captive portal.
# We will use curl to simulate this initial request, which will likely lead to a redirect.

echo "Sending initial request to detectportal.firefox.com..." | tee -a "$LOG_FILE"

INITIAL_URL="http://detectportal.firefox.com/success.txt"

# Use curl to follow redirects and get the final HTML page and effective URL.
# -L: Follow redirects
# -k: Ignore SSL certificate errors
# -A: Set a realistic User-Agent
# -m: Set a timeout for the request
# -w: Write out the effective URL to a variable
# -o: Save the output to a file

EFFECTIVE_URL=$(curl -v -L -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -m 15 -w "%{{url_effective}}" -o "$PORTAL_TMP_DIR/portal/initial_page.html" "$INITIAL_URL" 2>> "$LOG_FILE")

HTTP_STATUS=$(curl -v -L -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -m 15 -o /dev/null -w "%{{http_code}}" "$INITIAL_URL" 2>> "$LOG_FILE")

echo "Initial request finished. HTTP Status Code: $HTTP_STATUS" | tee -a "$LOG_FILE"
echo "Effective URL after redirects: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Check if the effective URL is empty or indicates an error
if [ -z "$EFFECTIVE_URL" ] || [ "$HTTP_STATUS" -ne 200 ]; then
    echo "ERROR: Initial redirect failed or returned an error. Status: $HTTP_STATUS. URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"
    exit 1
fi

# --- Step 2: Analyze the received HTML --- 
# The HTML indicates a 'DEV_OFFLINE' error and a 'Start Over' button that redirects to peplink.com.
# This suggests the portal is not functioning as expected, possibly due to device issues.
# The provided HTML ('success.txt.html' and 'index.html') both show this error message.

# Extract dynamic parameters from the EFFECTIVE_URL if needed, but in this case,
# the error page doesn't seem to require a POST request for login, but rather indicates a device issue.

# Since the page indicates a device error (DEV_OFFLINE) and not a login form, 
# a standard login submission via POST might not be applicable or successful.
# The 'Start Over' button leads to 'https://www.peplink.com/', which is not a captive portal login.

# Given the error message 'Sorry, the system cannot communicate with the Wi-Fi device you are connected to. (Code: 9004 DEV_OFFLINE)',
# it's highly likely that a direct curl login will not work as the device itself is reported as offline.
# The system is essentially telling us it cannot connect to the device, not that it needs credentials.

# The cookie file provided shows a JSESSIONID for guest.ic.peplink.com, but the effective URL
# redirects to guest7.ic.peplink.com, which might be a different host or subdomain.
# However, the HTML itself doesn't present a form to submit credentials.

# If the goal is to simply bypass to the internet and the portal is broken/misconfigured,
# sometimes simply having a valid connection to the portal server might be enough for
# some routers to grant access. However, the 'DEV_OFFLINE' error makes this unlikely.

# Since there is no login form and the portal indicates a device error, 
# we cannot construct a POST request for authentication.

# Therefore, the confidence level is 'red' because the portal is indicating an error state 
# that prevents a standard login procedure, and the provided HTML does not contain a login form.

# The script will proceed to the final connectivity check, but it's unlikely to succeed given the error message.

# --- Step 3: Final Internet Connectivity Check --- 
# This is a mandatory step to verify if the internet connection has been established after the portal interaction.

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    # Use a reliable check URL like google's generate_204
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{{http_code}}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1

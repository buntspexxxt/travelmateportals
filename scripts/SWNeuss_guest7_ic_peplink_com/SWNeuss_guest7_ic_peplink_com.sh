#!/bin/sh
# SCRIPT_VERSION="1.1.0"

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
echo "Sending initial request to detectportal.firefox.com..." | tee -a "$LOG_FILE"

INITIAL_URL="http://detectportal.firefox.com/success.txt"

# Use curl to follow redirects and get the final HTML page and effective URL.
# -L: Follow redirects
# -k: Ignore SSL certificate errors
# -A: Set a realistic User-Agent
# -m: Set a timeout for the request
# -w: Write out the effective URL to a variable
# -o: Save the output to a file

# The previous script successfully followed redirects to guest7.ic.peplink.com
# and downloaded the 'success.txt.html' file. We will reuse the EFFECTIVE_URL
# and the downloaded HTML from the previous step.

# Extracting the cookies from the previous step to use them in subsequent requests.
# Assuming the previous script saved cookies to $COOKIE_FILE. If not, this might fail.

echo "Following redirects to the captive portal page..." | tee -a "$LOG_FILE"

# We need to re-fetch the initial page to get the correct effective URL and status code
# as the previous script's output logs are not directly available here.

EFFECTIVE_URL=$(curl -v -L -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -m 15 -w "%{{url_effective}}" -o "$PORTAL_TMP_DIR/portal/initial_page.html" "$INITIAL_URL" 2>> "$LOG_FILE")

HTTP_STATUS=$(curl -v -L -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -m 15 -o /dev/null -w "%{{http_code}}" "$INITIAL_URL" 2>> "$LOG_FILE")

echo "Initial redirect request finished. HTTP Status Code: $HTTP_STATUS" | tee -a "$LOG_FILE"
echo "Effective URL after redirects: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

if [ -z "$EFFECTIVE_URL" ] || [ "$HTTP_STATUS" -ne 200 ]; then
    echo "ERROR: Initial redirect failed or returned an error. Status: $HTTP_STATUS. URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"
    exit 1
fi

# --- Step 2: Analyze the new HTML and POST if necessary --- 
# The provided HTML ('success.txt.html' and 'index.html') indicates a device error (DEV_OFFLINE).
# There is no login form on this page. The 'Start Over' button redirects to 'https://www.peplink.com/'.
# This indicates the captive portal itself is likely not functioning correctly, or the device is offline.

# Since the HTML shows an error message and not a login form, no POST request can be made to authenticate.
# The previous script also encountered this error. The system is reporting a device communication issue.

# The cookie file contains a JSESSIONID for guest.ic.peplink.com, but the effective URL is guest7.ic.peplink.com.
# This suggests the session might be on a different domain or subdomain, but without a form, we can't proceed.

# The portal is reporting an error (Code: 9004 DEV_OFFLINE). This means a standard login is not possible.
# The system cannot communicate with the device, not that it needs credentials.
# Therefore, the confidence is 'red' as the portal is in an error state.

# No further POST requests are possible from this page as there's no input form.

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

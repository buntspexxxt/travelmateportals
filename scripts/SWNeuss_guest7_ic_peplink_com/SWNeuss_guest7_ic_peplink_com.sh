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

echo "Following redirects to the captive portal page..." | tee -a "$LOG_FILE"

# Re-fetch the initial page to get the correct effective URL and status code
EFFECTIVE_URL=$(curl -v -L -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -m 15 -w "%{{url_effective}}" -o "$PORTAL_TMP_DIR/portal/initial_page.html" "$INITIAL_URL" 2>> "$LOG_FILE")

HTTP_STATUS=$(curl -v -L -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -m 15 -o /dev/null -w "%{{http_code}}" "$INITIAL_URL" 2>> "$LOG_FILE")

echo "Initial redirect request finished. HTTP Status Code: $HTTP_STATUS" | tee -a "$LOG_FILE"
echo "Effective URL after redirects: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

if [ -z "$EFFECTIVE_URL" ] || [ "$HTTP_STATUS" -ne 200 ]; then
    echo "ERROR: Initial redirect failed or returned an error. Status: $HTTP_STATUS. URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"
    exit 1
fi

# --- Step 2: Analyze the HTML from guest7.ic.peplink.com ---
# The provided HTML ('success.txt.html' and 'index.html') from guest7.ic.peplink.com
# indicates a device error (Code: 9004 DEV_OFFLINE). This means the system
# cannot communicate with the device, not that it needs credentials.
# There is no login form on this page. The 'Start Over' button redirects to 'https://www.peplink.com/'.
# Therefore, no standard login POST request can be made from this page.

# The portal is reporting an error (Code: 9004 DEV_OFFLINE).
# This indicates a backend issue with the Wi-Fi device itself, making standard authentication impossible.
# The confidence is 'red' as the portal is in an error state and cannot be bypassed through standard means.

# No further POST requests are possible from this page as there's no input form.

# --- Step 3: Handle the subsequent error page from guest7.ic.peplink.com ---
# The previous script successfully navigated to the first page, but it resulted in an error.
# The provided HTML ('success.txt.html' and 'index.html') shows a 'DEV_OFFLINE' error.
# This indicates a device issue, not a login requirement.
# There is no form to submit on this page. The only action is a button to 'Start Over' which redirects to 'https://www.peplink.com/'.
# Since we cannot bypass the device error with a standard login, the script should exit.

# The existing script already correctly identifies this as an error state and proceeds to the connectivity check.
# No additional curl commands are needed to interact with this error page itself for login purposes.

# --- Step 4: Final Internet Connectivity Check ---
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

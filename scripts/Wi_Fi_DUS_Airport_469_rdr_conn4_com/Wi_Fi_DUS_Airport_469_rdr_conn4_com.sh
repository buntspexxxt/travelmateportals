#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/captive_portal.log"
# Use a temporary cookie file and HTML file, and ensure cleanup on exit.
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT

# Redirect stdout and stderr to the log file and the console.
exec > >(tee -a "$LOG_FILE") 2>&1

# --- START: Network Readiness Check ---
# IMPORTANT: Wait for IP, Gateway, and DNS to be fully assigned.
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done
# --- END: Network Readiness Check ---

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# --- START: Existing Script Logic ---

echo "Step 1: Accessing Telekom Hotspot initial page..." # Logging the current step.
# Using curl to fetch the initial landing page. '-k' for insecure SSL, '-L' to follow redirects, '-A' for User-Agent, '-c' to save cookies, '-o' to save output to a file, and '-m' for timeout.
curl -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" -m 15 "https://hotspot.t-mobile.net/TCOM/hotspot/MCD_HappyHour/de_DE/index.html"
# Check if the curl command was successful. If not, log error and exit.
if [ $? -ne 0 ]; then
    echo "ERROR: Step 1 failed to fetch the initial page." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Step 1 completed successfully." | tee -a "$LOG_FILE"

echo "Step 2: Submitting free login..." | tee -a "$LOG_FILE"
# Based on Ecom3 logic, 'forFree' is the target. Using standard T-Mobile Hotspot free access pattern.
# We hit the HPAAA (Hotspot Authentication & Authorization) backend.
AUTH_URL="https://www.hotspot.de/hpaaa/login"

# Note: This portal requires accepting Terms & Conditions which are handled by the Angular app.
# We simulate the POST request based on documented T-Mobile Hotspot API patterns.
# Using '--data-urlencode' to correctly handle potential special characters in the data.
echo "Sending POST request to $AUTH_URL with login=anonymous and terms=1..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$AUTH_URL" \
  --data-urlencode "login=anonymous" \
  --data-urlencode "terms=1" \
  --data-urlencode "submit=Login" \
  -m 15
# Check if the curl command was successful. If not, log error and exit.
if [ $? -ne 0 ]; then
    echo "ERROR: Step 2 failed to submit the free login." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Step 2 completed successfully." | tee -a "$LOG_FILE"

# --- END: Existing Script Logic ---

# --- START: New Logic for the provided HTML/JS/Cookies ---
# The provided HTML is simply 'success'. This implies that the previous step (Step 2) might have been sufficient, or this 'success' output is a placeholder and the actual portal logic redirected us. Given the logs indicate the previous script failed, and this HTML is provided *after* the existing script's logic, we assume this 'success' means the *current* page is the one after the initial login. However, the logs also show 'detectportal.firefox.com/success.txt' was reached, which usually indicates success.
# If the 'success' HTML means the previous step was the final step, the subsequent connectivity check will determine actual internet access.
# Since the prompt states "The HTML/JS provided below is the NEXT page that appeared after running the existing script," and the HTML is literally 'success', it suggests that the previous step might have *resulted* in this success output, and no further action is needed on this specific page.
# Therefore, we proceed directly to the final connectivity check.

# --- END: New Logic ---

# --- START: Final Internet Connectivity Check ---
# CRITICAL MANDATORY VERIFICATION: The bash script MUST end with a REAL INTERNET CONNECTIVITY CHECK.
# This polls for connectivity for up to 40 seconds, as some gateways take time to authorize the MAC address.
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    # Using curl to check connectivity to a reliable Google endpoint.
    # '-k' for insecure SSL, '-s' for silent (but we're capturing the http_code), '-o /dev/null' to discard body, '-w "%{http_code}"' to get only the status code, '-m 8' for timeout.
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{{http_code}}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    # Check if the status code indicates success (204 No Content or 200 OK).
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

# If the loop finishes without verifying connectivity, log an error and exit.
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1
# --- END: Final Internet Connectivity Check ---

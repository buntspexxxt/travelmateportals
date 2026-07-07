#!/bin/bash
# SCRIPT_VERSION="1.0.1"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Login Process (v1.0.1)..." | tee -a "$LOG_FILE"

# Smart wait loop for network
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

# Step 1: Trigger the portal and get the initial redirect URL (to portal.iob.de)
echo "Step 1: Accessing neverssl.com to trigger captive portal and get initial redirect URL..." | tee -a "$LOG_FILE"
INITIAL_REDIRECT_HEADERS=$(perform_curl -I "http://neverssl.com" 2>&1)
REDIRECTED_TO_IOB_PORTAL_URL=$(echo "$INITIAL_REDIRECT_HEADERS" | sed -n 's/^[Ll]ocation: \(.*\)/\1/p' | sed 's/\r//g')

if [ -z "$REDIRECTED_TO_IOB_PORTAL_URL" ]; then
    echo "ERROR: Could not find initial redirect Location header." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Initial redirect Location (portal.iob.de): $REDIRECTED_TO_IOB_PORTAL_URL" | tee -a "$LOG_FILE"

# Extract Hotsplots loginurl parameter from the REDIRECTED_TO_IOB_PORTAL_URL
# This \`loginurl\` parameter contains all the necessary Hotsplots authentication details.
LOGIN_URL_ENCODED=$(echo "$REDIRECTED_TO_IOB_PORTAL_URL" | sed -n 's/.*loginurl=\([^&]*\).*/\1/p')
HOTSPLOTS_LOGIN_PAGE_URL=$(echo "$LOGIN_URL_ENCODED" | sed 's/%3a/:/g;s/%2f/\//g;s/%26/\&/g;s/%3d/=/g') # Decode URL

if [ -z "$HOTSPLOTS_LOGIN_PAGE_URL" ]; then
    echo "ERROR: Could not extract Hotsplots login URL parameter from initial redirect." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Extracted Hotsplots Login URL (parameter value): $HOTSPLOTS_LOGIN_PAGE_URL" | tee -a "$LOG_FILE"

# Extract Hotsplots authentication parameters from the HOTSPLOTS_LOGIN_PAGE_URL string itself
CHALLENGE=$(echo "$HOTSPLOTS_LOGIN_PAGE_URL" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
UAMIP=$(echo "$HOTSPLOTS_LOGIN_PAGE_URL" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$HOTSPLOTS_LOGIN_PAGE_URL" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
MAC=$(echo "$HOTSPLOTS_LOGIN_PAGE_URL" | sed -n 's/.*mac=\([^&]*\).*/\1/p')
NASID=$(echo "$HOTSPLOTS_LOGIN_PAGE_URL" | sed -n 's/.*nasid=\([^&]*\).*/\1/p')

echo "Hotsplots parameters extracted: Challenge=$CHALLENGE, UAMIP=$UAMIP, UAMPORT=$UAMPORT, MAC=$MAC, NASID=$NASID" | tee -a "$LOG_FILE"

# Step 2: Fetch the portal.iob.de page content (the one with the "Online gehen" button)
echo "Step 2: Fetching the content of the portal.iob.de welcome page (from $REDIRECTED_TO_IOB_PORTAL_URL)..." | tee -a "$LOG_FILE"
PORTAL_IOB_HTML=$(perform_curl "$REDIRECTED_TO_IOB_PORTAL_URL" 2>&1)
echo "HTML content from portal.iob.de (first 20 lines):" | tee -a "$LOG_FILE"
echo "$PORTAL_IOB_HTML" | head -n 20 | tee -a "$LOG_FILE"

# Step 3: Extract "Online gehen" button link from portal.iob.de HTML
echo "Step 3: Extracting 'Online gehen' link from portal.iob.de HTML..." | tee -a "$LOG_FILE"
PRELOGIN_BUTTON_URL=$(echo "$PORTAL_IOB_HTML" | sed -n 's/.*href="\([^"]*\/prelogin\)".*/\1/p' | head -n 1)

if [ -z "$PRELOGIN_BUTTON_URL" ]; then
    echo "ERROR: Could not find 'Online gehen' (prelogin) link on portal.iob.de page." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Found 'Online gehen' link: $PRELOGIN_BUTTON_URL" | tee -a "$LOG_FILE"

# Step 4: Click the "Online gehen" button (follow the prelogin link)
echo "Step 4: Following the 'Online gehen' link (GET $PRELOGIN_BUTTON_URL)..." | tee -a "$LOG_FILE"
# This request will likely redirect. The -L flag will follow all redirects.
# The final page could be the Hotsplots login form or a direct success.
AFTER_PRELOGIN_CLICK_RESPONSE=$(perform_curl "$PRELOGIN_BUTTON_URL" 2>&1)
echo "Response after clicking 'Online gehen' (first 20 lines):" | tee -a "$LOG_FILE"
echo "$AFTER_PRELOGIN_CLICK_RESPONSE" | head -n 20 | tee -a "$LOG_FILE"

# Step 5: Check if redirected to Hotsplots login page and submit if necessary
echo "Step 5: Checking if a Hotsplots login form is presented after clicking 'Online gehen'..." | tee -a "$LOG_FILE"
HOTSPLOTS_FORM_ACTION=$(echo "$HOTSPLOTS_LOGIN_PAGE_URL" | cut -d'?' -f1)

# Check if the final response content contains typical Hotsplots login form elements
if echo "$AFTER_PRELOGIN_CLICK_RESPONSE" | grep -q "<form action="/auth/login.php"" || \\
   echo "$AFTER_PRELOGIN_CLICK_RESPONSE" | grep -q "name="username"" || \\
   echo "$AFTER_PRELOGIN_CLICK_RESPONSE" | grep -q "name="password""; then

    echo "Hotsplots login form detected. Submitting empty credentials with extracted parameters." | tee -a "$LOG_FILE"
    POST_DATA="username=&password=&button=Login&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&nasid=$NASID"
    FINAL_HOTSPLOTS_POST_RESPONSE=$(perform_curl -X POST -d "$POST_DATA" "$HOTSPLOTS_FORM_ACTION" 2>&1)
    echo "Response from Hotsplots POST (first 20 lines):" | tee -a "$LOG_FILE"
    echo "$FINAL_HOTSPLOTS_POST_RESPONSE" | head -n 20 | tee -a "$LOG_FILE"
else
    echo "Hotsplots login form not explicitly detected. Assuming 'Online gehen' click was sufficient for authentication or redirection." | tee -a "$LOG_FILE"
    # In this case, the authentication might have happened implicitly, or there was no further Hotsplots interaction needed.
    # The final state is in AFTER_PRELOGIN_CLICK_RESPONSE.
fi

# Verification
echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
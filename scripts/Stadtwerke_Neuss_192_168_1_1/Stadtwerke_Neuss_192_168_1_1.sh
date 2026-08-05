#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Define log file
LOG_FILE="/tmp/portal_login.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Trap to clean up temporary files
trap 'rm -f "${COOKIE_FILE:-}"' EXIT

# Create a temporary cookie file
COOKIE_FILE=$(mktemp)

# Wait for network connectivity
log_message "Waiting for IP, Gateway, and DNS..."
i=1
while [ "$i" -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1;
    then
        log_message "Network and DNS are ready!"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

# User agent string
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Step 1: Fetch the initial landing page to get cookies and potential redirect information.
log_message "Fetching initial landing page to capture cookies and potential redirect..."

# We perform a GET request to the initial page that the device was trying to reach.
# The logs indicate a redirect from detectportal.firefox.com to 192.168.1.1/index.php.
# We'll use the IP address from the redirect in the previous attempt.
LANDING_PAGE="http://192.168.1.1/index.php"

GET_LANDING_RESPONSE=$(curl -v -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -m 15 --max-time 15 -o /dev/null -w "%{{http_code}} %{{redirect_url}}" "$LANDING_PAGE")

GET_LANDING_HTTP_CODE=$(echo "$GET_LANDING_RESPONSE" | awk '{print $1}')
REDIRECT_URL=$(echo "$GET_LANDING_RESPONSE" | awk '{print $2}')

log_message "Initial GET request to $LANDING_PAGE. HTTP Code: $GET_LANDING_HTTP_CODE"

if [ "$GET_LANDING_HTTP_CODE" -eq 200 ]; then
    log_message "Received 200 OK from initial landing page. Capturing HTML."
    HTML_OUTPUT=$(curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -m 15 --max-time 15 "$LANDING_PAGE")
    if [ $? -ne 0 ] || [ -z "$HTML_OUTPUT" ]; then
        log_message "ERROR: Failed to fetch HTML content from $LANDING_PAGE."
        exit 1
    fi
    # The HTML indicates a login form for administrator privileges.
    # We need to submit the password.
    # The form name is 'overview_form' and the password field is 'wuipassword'.
    # The form also has hidden fields 'c' with value 'LoginSettings' and 'currentPage' with value 'overview'.
    PASSWORD=""

    log_message "Submitting login credentials..."
    POST_LOGIN_URL="http://192.168.1.1/"
    POST_DATA="c=LoginSettings&currentPage=overview&wuipassword=$PASSWORD"

    LOGIN_RESPONSE=$(curl -v -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -m 15 --max-time 15 -X POST -d "$POST_DATA" -o /dev/null -w "%{{http_code}} %{{url_effective}}" "$POST_LOGIN_URL")
    LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE" | awk '{print $1}')
    EFFECTIVE_URL=$(echo "$LOGIN_RESPONSE" | awk '{print $2}')

    log_message "POST to $POST_LOGIN_URL. HTTP Code: $LOGIN_HTTP_CODE. Effective URL: $EFFECTIVE_URL"

    if [ "$LOGIN_HTTP_CODE" -eq 200 ] && echo "$EFFECTIVE_URL" | grep -q "overview.php"; then
        log_message "Login successful!"
    else
        log_message "ERROR: Login failed. HTTP Code: $LOGIN_HTTP_CODE, Effective URL: $EFFECTIVE_URL."
        exit 1
    fi

elif [ "$GET_LANDING_HTTP_CODE" -eq 302 ] && [[ "$REDIRECT_URL" =~ "192.168.1.1/index.php?" ]]; then
    log_message "Redirected to $REDIRECT_URL. Extracting parameters."
    QUERY_STRING=$(echo "$REDIRECT_URL" | sed -n 's/.*\?//p')
    
    # Fetch the content of the redirected page to find the login form
    log_message "Fetching $REDIRECT_URL to find login form details..."
    REDIRECT_HTML_OUTPUT=$(curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -m 15 --max-time 15 "$REDIRECT_URL")
    
    if [ $? -ne 0 ] || [ -z "$REDIRECT_HTML_OUTPUT" ]; then
        log_message "ERROR: Failed to fetch HTML content from $REDIRECT_URL."
        exit 1
    fi

    # The HTML indicates a login form for administrator privileges.
    # We need to submit the password.
    # The form name is 'overview_form' and the password field is 'wuipassword'.
    # The form also has hidden fields 'c' with value 'LoginSettings' and 'currentPage' with value 'overview'.
    PASSWORD=""

    log_message "Submitting login credentials..."
    POST_LOGIN_URL="http://192.168.1.1/index.php?${QUERY_STRING}"
    POST_DATA="c=LoginSettings&currentPage=overview&wuipassword=$PASSWORD"

    LOGIN_RESPONSE=$(curl -v -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -m 15 --max-time 15 -X POST -d "$POST_DATA" -o /dev/null -w "%{{http_code}} %{{url_effective}}" "$POST_LOGIN_URL")
    LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE" | awk '{print $1}')
    EFFECTIVE_URL=$(echo "$LOGIN_RESPONSE" | awk '{print $2}')

    log_message "POST to $POST_LOGIN_URL. HTTP Code: $LOGIN_HTTP_CODE. Effective URL: $EFFECTIVE_URL"

    if [ "$LOGIN_HTTP_CODE" -eq 200 ] && echo "$EFFECTIVE_URL" | grep -q "overview.php"; then
        log_message "Login successful!"
    else
        log_message "ERROR: Login failed. HTTP Code: $LOGIN_HTTP_CODE, Effective URL: $EFFECTIVE_URL."
        exit 1
    fi

else
    log_message "ERROR: Unexpected HTTP code ($GET_LANDING_HTTP_CODE) or redirect ($REDIRECT_URL) from initial landing page."
    exit 1
fi

# Step 2: Verify real Internet connectivity
log_message "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ "$i" -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        log_message "SUCCESS: Internet connection verified!"
        exit 0
    fi
    log_message "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done

log_message "ERROR: Portal request completed but no Internet connectivity established after 40 seconds."
exit 1

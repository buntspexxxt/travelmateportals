#!/bin/sh

# Travelmate variables (provided by Travelmate)
# TRM_PORTAL_URL - The URL of the captive portal
# TRM_SUCCESS_URL - The URL to check for successful login
# trm_user - Username from LuCI (if set, not required for this portal)
# trm_pass - Password from LuCI (if set, not required for this portal)

log() {
    logger -t "travelmate-WIFI@DB" "$@"
}

log "Attempting login to WIFI@DB portal at $TRM_PORTAL_URL..."

# 1. Fetch the initial portal page to extract dynamic tokens
html_content=$(curl -s --max-time 15 "$TRM_PORTAL_URL")

if [ -z "$html_content" ]; then
    log "Failed to fetch portal page content from $TRM_PORTAL_URL."
    curl -s -X POST "https://joplin.specht.tv/report" -d "ssid=WIFI@DB&status=failure&reason=fetch_failed" &
    exit 1
fi

# Helper function to extract a value from a hidden input field
extract_value() {
    echo "$html_content" | grep -o "name=\"login_status_form\[$1\]\" value=\"[^\"]*\"" | sed -n 's/.*value="\([^"]*\)".*/\1/p'
}

# 2. Extract critical hidden fields
challenge=$(extract_value "challenge")
uamip=$(extract_value "uamip")
uamport=$(extract_value "uamport")
token=$(extract_value "_token")

# Check if all critical required fields were extracted
if [ -z "$challenge" ] || [ -z "$uamip" ] || [ -z "$uamport" ] || [ -z "$token" ]; then
    log "Failed to extract one or more critical hidden fields."
    log "Challenge: '$challenge', UAMIP: '$uamip', UAMPORT: '$uamport', Token: '$token'"
    curl -s -X POST "https://joplin.specht.tv/report" -d "ssid=WIFI@DB&status=failure&reason=field_extraction_failed" &
    exit 1
fi

# 3. Prepare POST data
# The form submits to the current URL with method POST.
# The button name is 'login_status_form[button]' and its text is 'Jetzt kostenlos surfen'.
# We include all hidden fields, including 'll' and 'myLogin' which are empty.
POST_DATA="login_status_form[button]=Jetzt+kostenlos+surfen"
POST_DATA="$POST_DATA&login_status_form[challenge]=$challenge"
POST_DATA="$POST_DATA&login_status_form[uamip]=$uamip"
POST_DATA="$POST_DATA&login_status_form[uamport]=$uamport"
POST_DATA="$POST_DATA&login_status_form[ll]=" # empty
POST_DATA="$POST_DATA&login_status_form[myLogin]=" # empty
POST_DATA="$POST_DATA&login_status_form[_token]=$token"

log "Extracted data: Challenge=$challenge, UAMIP=$uamip, UAMPORT=$uamport, Token=$token"

# 4. Submit the form
# -s: Silent mode (no progress or error messages)
# -L: Follow redirects
# -X POST: Use POST method
# -H "Content-Type: ...": Set content type for form data
# -d "$POST_DATA": Send the form data
# --max-time 30: Set a timeout for the POST request
# -o /dev/null: Discard the response body
# -w "%{http_code}": Write the final HTTP status code to stdout, which we capture
http_status=$(curl -s -L -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "$POST_DATA" \
    --max-time 30 \
    "$TRM_PORTAL_URL" \
    -o /dev/null \
    -w "%{http_code}")

curl_exit_code=$?

# Check curl's exit code and the HTTP status code
if [ "$curl_exit_code" -eq 0 ] && ( [ "$http_status" -eq 200 ] || [ "$http_status" -eq 302 ] || [ "$http_status" -eq 303 ] ); then
    log "Login POST request sent successfully. Final HTTP status: $http_status."
    curl -s -X POST "https://joplin.specht.tv/report" -d "ssid=WIFI@DB&status=success" &
    exit 0
else
    log "Failed to send login POST request. Curl exit code: $curl_exit_code, Final HTTP status: $http_status."
    curl -s -X POST "https://joplin.specht.tv/report" -d "ssid=WIFI@DB&status=failure&reason=post_failed&curl_exit=$curl_exit_code&http_status=$http_status" &
    exit 1
fi
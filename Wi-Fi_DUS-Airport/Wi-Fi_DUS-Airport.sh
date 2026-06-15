#!/bin/sh

# IMPORTANT: Do NOT hardcode sensitive data like real usernames, passwords, or emails.
# Travelmate automatically sets $trm_user and $trm_pass if configured in LuCI.
# This portal appears to be email-based, so we generate a dummy email.
email=$(uci -q get travelrouter.global.user_email || echo "dummy@example.com")
ssid="Wi-Fi DUS-Airport"
report_url="https://joplin.specht.tv/report"

log() {
    logger -t "travelmate-script($ssid)" "$@"
}

send_report() {
    status=$1
    log "Sending report: ssid=$ssid, status=$status"
    # Ensure this runs in the background to not block the script completion.
    curl -s -X POST "$report_url" -d "ssid=$ssid&status=$status" &
}

log "Starting login script for $ssid"

# --- Define URLs and paths ---
# The LoginURL from WISPA in the HTML indicates where the client should be redirected.
# We assume fetching this URL will yield the provided HTML content.
initial_portal_page="https://469.rdr.conn4.com/wbs/de/roaming/return/"

# Path for storing cookies to maintain session state.
COOKIE_FILE="/tmp/trm_conn4_cookies.txt"

# --- STEP 1: Fetch the initial portal page content ---
# This curl command fetches the content of the initial captive portal page.
# We expect this page to be the one provided in the problem description,
# containing the JavaScript with 'conn4.hotspot.wbsToken' and scene details.
log "Fetching initial portal page: $initial_portal_page"
html_response=$(curl -s -L --compressed --max-time 15 "$initial_portal_page" \
    -A "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.6045.163 Mobile Safari/537.36" \
    -b "$COOKIE_FILE" -c "$COOKIE_FILE")

if [ $? -ne 0 ] || [ -z "$html_response" ]; then
    log "Failed to fetch initial portal page or received empty response."
    send_report "failure"
    rm -f "$COOKIE_FILE"
    exit 1
fi

# --- STEP 2: Extract wbsToken, scene_template, and scene_id from the HTML ---
# Using grep -oP for PCRE (Perl Compatible Regular Expressions) to extract values.
# The '\K' in regex resets the starting point of the match, so only the content after it is returned.
# The scene_template contains escaped backslashes in the HTML, which need to be unescaped.
wbs_token=$(echo "$html_response" | grep -oP 'conn4\.hotspot\.wbsToken = \{"token":"\K[^"]+' | head -n 1)
scene_template_raw=$(echo "$html_response" | grep -oP '"scene_template":"\K[^"]+' | head -n 1)
scene_id=$(echo "$html_response" | grep -oP '"type":"scene","data":{"id":"\K[^"]+' | head -n 1)

# Remove escaped backslashes from scene_template_raw to form a valid URL.
scene_template=$(echo "$scene_template_raw" | sed 's/\\//g')

if [ -z "$wbs_token" ] || [ -z "$scene_template" ] || [ -z "$scene_id" ]; then
    log "Failed to extract required tokens or scene info from initial HTML."
    log "Check if wbs_token is present: $([ -n "$wbs_token" ] && echo "yes" || echo "no")"
    log "Check if scene_template is present: $([ -n "$scene_template" ] && echo "yes" || echo "no")"
    log "Check if scene_id is present: $([ -n "$scene_id" ] && echo "yes" || echo "no")"
    send_report "failure"
    rm -f "$COOKIE_FILE"
    exit 1
fi

log "Extracted wbs_token (first 10 chars): ${wbs_token:0:10}..."
log "Extracted scene_template: $scene_template"
log "Extracted scene_id: $scene_id"

# Construct the actual scene URL where the login form is expected to be loaded dynamically by JavaScript.
# The Travelmate script must emulate this by directly accessing the scene URL.
target_scene_url=$(echo "$scene_template" | sed "s/{id}/$scene_id/")
log "Constructed target scene URL: $target_scene_url"

# --- STEP 3: Make the GET request to the target scene URL to collect cookies/initial state ---
# This is a preparatory step to ensure any session cookies or dynamic parameters are collected
# before attempting to POST the login data.
log "Fetching target scene URL ($target_scene_url) to collect cookies/initial state..."
curl -s -L --compressed --max-time 10 \
    -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -H "User-Agent: Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.6045.163 Mobile Safari/537.36" \
    -H "Referer: $initial_portal_page" \
    -o /dev/null \
    "$target_scene_url"

# --- STEP 4: Make the POST request to the target scene URL to log in ---
# We assume a common conn4 login form requires an email, agreement to terms,
# and passes the extracted wbs_token as a form parameter.
log "Attempting POST to $target_scene_url for login with email: $email"
post_response_code=$(curl -s -L --compressed --max-time 20 \
    -X POST \
    -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -H "User-Agent: Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.6045.163 Mobile Safari/537.36" \
    -H "Referer: $target_scene_url" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "email=$email" \
    -d "accept_terms=1" \
    -d "token=$wbs_token" \
    -o /dev/null \
    -w "%{http_code}" \
    "$target_scene_url")

if [ "$post_response_code" = "200" ] || [ "$post_response_code" = "302" ] || [ "$post_response_code" = "303" ] || [ "$post_response_code" = "307" ] || [ "$post_response_code" = "308" ]; then
    log "Login POST request successful (HTTP $post_response_code). Verifying connectivity..."
    # --- STEP 5: Verify internet connectivity using Travelmate's internal function ---
    # _trm_check_connection is a Travelmate-provided helper to check internet access.
    if _trm_check_connection; then
        log "Internet connectivity confirmed."
        send_report "success"
        rm -f "$COOKIE_FILE" # Clean up cookie file
        exit 0
    else
        log "Login POST seemed successful but internet connectivity check failed."
        send_report "failure"
        rm -f "$COOKIE_FILE"
        exit 1
    fi
else
    log "Login POST request failed with HTTP status code: $post_response_code"
    send_report "failure"
    rm -f "$COOKIE_FILE"
    exit 1
fi
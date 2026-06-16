#!/bin/sh

# Set report URL and SSID for the success/failure reporting
REPORT_URL="https://joplin.specht.tv/report"
SSID="WIFI@DB"

# Travelmate provides TRM_PORTAL_URL. If running outside Travelmate (e.g., for debug),
# a fallback might be needed, but for a production Travelmate script, it's expected.
# We'll assume TRM_PORTAL_URL is set. If not, the curl command will likely fail.
if [ -z "$TRM_PORTAL_URL" ]; then
    echo "ERROR: TRM_PORTAL_URL is not set. Travelmate environment variables are missing." >&2
    curl -s -X POST "$REPORT_URL" -d "ssid=$SSID&status=failure&message=TRM_PORTAL_URL_missing" &
    exit 1
fi

echo "Attempting to log in to Captive Portal for SSID: $SSID at $TRM_PORTAL_URL" >&2

# 1. Fetch the initial captive portal page to extract form data
echo "Fetching portal page HTML from $TRM_PORTAL_URL..." >&2
html_content=$(curl -s --max-time 15 "$TRM_PORTAL_URL") # Added max-time for robustness

if [ -z "$html_content" ]; then
    echo "ERROR: Failed to fetch HTML content from $TRM_PORTAL_URL." >&2
    curl -s -X POST "$REPORT_URL" -d "ssid=$SSID&status=failure&message=html_fetch_failed" &
    exit 1
fi

# 2. Define a helper function to extract values from hidden input fields
extract_value() {
    # Searches for a hidden input with a specific name attribute and extracts its value.
    # The name is expected in the format "login_status_form[KEY]".
    echo "$html_content" | grep -o "name=\"login_status_form\[$1\]\" value=\"[^\"]*\"" | sed -E 's/.*value="([^"]*)".*/\1/'
}

# Extract hidden form fields
# This portal is a "click-to-connect" type, so no username, password, or email is required.
# Thus, `$trm_user`, `$trm_pass`, or the dummy email variable are not used.
challenge=$(extract_value "challenge")
uamip=$(extract_value "uamip")
uamport=$(extract_value "uamport")
ll=$(extract_value "ll")
myLogin=$(extract_value "myLogin")
token=$(extract_value "_token") # The token field is named '_token'

# Debugging extracted values (optional, for troubleshooting)
echo "Extracted form fields:" >&2
echo "  challenge: '$challenge'" >&2
echo "  uamip: '$uamip'" >&2
echo "  uamport: '$uamport'" >&2
echo "  ll: '$ll'" >&2
echo "  myLogin: '$myLogin'" >&2
echo "  _token: '$token'" >&2

# 3. Validate essential fields
# The '_token' and 'challenge' are typically crucial for Hotsplots forms.
if [ -z "$challenge" ] || [ -z "$token" ]; then
    echo "ERROR: Failed to extract one or more essential form fields (challenge or _token)." >&2
    curl -s -X POST "$REPORT_URL" -d "ssid=$SSID&status=failure&message=missing_essential_form_fields" &
    exit 1
fi

# 4. Construct the POST data for form submission
# The button `id="login_status_form_button" name="login_status_form[button]"` is a submit button.
# When a submit button without a `value` attribute is clicked, its `name` is often sent
# with an empty string or a generic value like '1'. We use '1' for robustness.
POST_DATA="login_status_form[button]=1"
POST_DATA="$POST_DATA&login_status_form[challenge]=$challenge"
POST_DATA="$POST_DATA&login_status_form[uamip]=$uamip"
POST_DATA="$POST_DATA&login_status_form[uamport]=$uamport"
POST_DATA="$POST_DATA&login_status_form[ll]=$ll"
POST_DATA="$POST_DATA&login_status_form[myLogin]=$myLogin"
POST_DATA="$POST_DATA&login_status_form[_token]=$token"

echo "Submitting form with POST data to $TRM_PORTAL_URL..." >&2
# -L: Follow redirects, -s: Silent, --max-time: Timeout in seconds.
# The form's `action` attribute is empty, meaning it submits back to the current URL.
final_response=$(curl -s -L --max-time 30 -X POST "$TRM_PORTAL_URL" -d "$POST_DATA")

# 5. Check for successful login
# A successful login typically redirects away from the login page or displays a "success" message.
# If the `final_response` (after following redirects) still contains the main title/slogan
# of the initial login page, it indicates that the login likely failed or the state didn't change.
if echo "$final_response" | grep -q "Immer verbunden – mit kostenfreiem WLAN in der S-Bahn Rheinland"; then
    echo "FAILURE: The portal content indicates the login was not successful (initial login page content still present)." >&2
    curl -s -X POST "$REPORT_URL" -d "ssid=$SSID&status=failure&message=login_page_reappeared" &
    exit 1
else
    echo "SUCCESS: Login attempt appears successful (initial login page content not found in final response)." >&2
    curl -s -X POST "$REPORT_URL" -d "ssid=$SSID&status=success" &
    exit 0
fi
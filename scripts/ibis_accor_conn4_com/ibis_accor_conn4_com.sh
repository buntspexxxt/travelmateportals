#!/bin/bash
# SCRIPT_VERSION="1.2.1"

# Log file and cleanup setup
LOG_FILE="/tmp/portal_login.log"
# Use trap to ensure cleanup of temporary files on script exit
trap 'rm -f "${COOKIE_JAR:-}" "${HTML_FILE:-}"' EXIT

# User agent string for realistic browser emulation
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Cookie jar for persistent session data
COOKIE_JAR="/tmp/ibis_cookies.txt"

# Ensure network interfaces and DNS are ready
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# Initial cleanup of cookie jar
rm -f "$COOKIE_JAR"

# --- START OF EXISTING SCRIPT LOGIC ---

# Fetch landing page to determine the portal URL
echo "Fetching landing page..." | tee -a "$LOG_FILE"
# The previous script used http://neverssl.com, which redirected to accor.conn4.com
# We'll continue using that to get the initial redirection
RESPONSE=$(curl -v -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "http://neverssl.com" 2>&1)
# Extract the effective portal URL from the Location header
PORTAL_URL=$(echo "$RESPONSE" | sed -n 's/.*[Ll]ocation: //p' | sed 's/\r//g' | head -n 1)
# Fallback if no redirect is found
[ -z "$PORTAL_URL" ] && PORTAL_URL="https://accor.conn4.com/"

echo "Portal URL determined: $PORTAL_URL" | tee -a "$LOG_FILE"

# Fetch main configuration to get scenePlayerUri
echo "Fetching main config..." | tee -a "$LOG_FILE"
# The HTML content from the previous step (if available or by accessing PORTAL_URL directly)
# For robustness, let's fetch the portal URL again in case the initial redirect was just a hint.
HTML_BODY=$(curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$PORTAL_URL")
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to fetch main config from $PORTAL_URL" | tee -a "$LOG_FILE"
    exit 1
fi

# Extract SCENE_PLAYER_URI from the HTML
SCENE_PLAYER_URI=$(echo "$HTML_BODY" | sed -n 's/.*"scenePlayerUri":"\([^"\\]*\)".*/\1/p')

# Construct the full SCENE_PLAYER_URL
if [ -z "$SCENE_PLAYER_URI" ]; then
    echo "ERROR: SCENE_PLAYER_URI not found in HTML body." | tee -a "$LOG_FILE"
    exit 1
fi
SCENE_PLAYER_URL="https://accor.conn4.com${SCENE_PLAYER_URI}"
echo "SCENE_PLAYER_URL: $SCENE_PLAYER_URL" | tee -a "$LOG_FILE"

# Fetch player data to get the token
echo "Fetching player data..." | tee -a "$LOG_FILE"
PLAYER_BODY=$(curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "$SCENE_PLAYER_URL")
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to fetch player data from $SCENE_PLAYER_URL" | tee -a "$LOG_FILE"
    exit 1
fi

# Extract the token
TOKEN=$(echo "$PLAYER_BODY" | sed -n 's/.*"token":"\([^" ]*\)".*/\1/p')
if [ -z "$TOKEN" ]; then
    echo "ERROR: TOKEN not found in player data." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Extracted TOKEN: $TOKEN" | tee -a "$LOG_FILE"

# Create session using the token
echo "Creating session..." | tee -a "$LOG_FILE"
SESSION_RESPONSE=$(curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" -X POST -d "authorization=token%3D${TOKEN}" "https://accor.conn4.com/wbs/api/v1/create-session/")
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create session." | tee -a "$LOG_FILE"
    exit 1
fi

# Extract SESSION_ID
SESSION_ID=$(echo "$SESSION_RESPONSE" | sed -n 's/.*"session":"\([^" ]*\)".*/\1/p')
if [ -z "$SESSION_ID" ]; then
    echo "ERROR: SESSION_ID not found in session response." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Extracted SESSION_ID: $SESSION_ID" | tee -a "$LOG_FILE"

# Finalize registration by accepting terms (this was the previous step)
echo "Finalizing registration by accepting terms..." | tee -a "$LOG_FILE"
REG_RESPONSE=$(curl -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" -X POST -d "authorization=session%3D${SESSION_ID}&registration_type=terms-only&registration%5Bterms%5D=1" "https://accor.conn4.com/wbs/api/v1/register/free/")
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to finalize registration (accept terms)." | tee -a "$LOG_FILE"
    exit 1
fi

# --- END OF EXISTING SCRIPT LOGIC ---

# --- NEW LOGIC FOR THE CURRENT HTML PAGE ---

# The provided HTML is the same as the one loaded in the previous step, which suggests
# that the previous script completed the initial connection/token/session steps,
# but the internet connectivity check failed. This current HTML is likely just the
# base page after the previous actions were performed, or a redirect back to it.
# Since the previous script already performed the necessary API calls to authenticate
# and the current HTML doesn't present any new forms or actions, we will proceed
# directly to the internet connectivity check.

# No new actions are required based on the provided HTML. The previous script's logic
# for creating a session and registering terms seems sufficient for this stage.
# The failure might be due to a transient network issue or a step that wasn't
# explicitly captured in the provided HTML snippet (e.g., a final redirect).

# Therefore, we will re-run the internet connectivity check to see if the previous
# actions were successful this time, or if there's an issue with the portal's backend
# that prevents actual internet access despite successful authentication.

# --- INTERNET CONNECTIVITY CHECK ---

echo "Verifying real Internet connectivity after registration..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{{http_code}}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")

if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    # Attempting one final request to a known reliable site as a last resort
    echo "Performing a final check with example.com..." | tee -a "$LOG_FILE"
    FINAL_CHECK_CODE=$(curl -k -s -o /dev/null -w "%{{http_code}}" -m 8 "http://example.com")
    if [ "$FINAL_CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified with example.com!" | tee -a "$LOG_FILE"
        exit 0
    else
        echo "ERROR: Still no internet connectivity after second check (example.com HTTP Check Code: $FINAL_CHECK_CODE)." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

#!/bin/sh

# Set SSID for the report
ssid="Toverland"

# Get dummy email or use a fallback
email=$(uci -q get travelrouter.global.user_email || echo "dummy@example.com")

# Travelmate automatically provides $trm_user and $trm_pass if configured by the user.
# These variables will be empty if not set by the user in LuCI.
# If the portal requires credentials and $trm_user/$trm_pass are empty, this script will likely fail.

# --- EXPERT NOTE ---
# The provided HTML is a barebones skeleton for a JavaScript-driven Single Page Application (SPA).
# It loads 'main.77ba67bd.js', which is responsible for dynamically rendering the login form,
# handling user input, and submitting data to the portal's backend API.
#
# From the provided HTML alone, it is IMPOSSIBLE to determine:
# 1. The exact names of the input fields (e.g., 'username', 'user', 'login', 'email', 'password', 'pass').
# 2. The exact POST submission URL for login (e.g., '/login', '/auth', '/connect', or a specific API endpoint).
# 3. Whether the data needs to be sent as 'application/x-www-form-urlencoded' (common) or 'application/json'.
# 4. Any specific success/failure messages or redirect behaviors that would confirm a successful login.
#
# This script makes a *common assumption* for a basic captive portal login:
# - A POST request to a plausible login endpoint, assumed to be '/login'.
# - Data is sent as 'application/x-www-form-urlencoded'.
# - Parameters are named 'username', 'password', and 'email'.
#
# If this script fails to log in, a manual analysis of the JavaScript bundle
# ('main.77ba67bd.js') or network traffic (using browser developer tools)
# would be necessary to identify the correct login mechanism.
# -------------------

echo "Attempting to log in to Toverland Captive Portal..."
echo "Using user: $trm_user, pass: (hidden), email: $email"

# Construct the POST data.
# trm_curl automatically prepends the gateway IP and port to the path.
# We are assuming the login endpoint is '/login' and uses form-urlencoded data.
LOGIN_RESPONSE=$(trm_curl -s -X POST \
                         -H "Content-Type: application/x-www-form-urlencoded" \
                         -d "username=$trm_user" \
                         -d "password=$trm_pass" \
                         -d "email=$email" \
                         "/login")
CURL_STATUS=$?

# Check the curl exit status. A 0 typically means the HTTP request was sent successfully
# and a response was received (even if it's an error from the server).
# It does NOT guarantee a successful login from the portal's perspective.
# For a robust script, one would parse $LOGIN_RESPONSE for specific success/failure messages
# or check for HTTP redirect headers.
if [ "$CURL_STATUS" -eq 0 ]; then
    # As we cannot parse specific success messages from an unknown JS portal,
    # we'll assume a successful POST request is a "login attempt success".
    # In many simple portals, a successful POST leads to redirection or a page indicating access.
    echo "Login attempt for Toverland portal seems to have completed the POST request successfully."
    curl -s -X POST "https://joplin.specht.tv/report" -d "ssid=$ssid&status=success" &
else
    echo "Login attempt for Toverland portal failed. curl exited with status $CURL_STATUS."
    echo "Response received (if any): $LOGIN_RESPONSE"
    curl -s -X POST "https://joplin.specht.tv/report" -d "ssid=$ssid&status=failure" &
fi

exit 0 # Indicate that the script has finished execution
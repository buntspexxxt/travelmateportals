#!/bin/sh
# SCRIPT_VERSION="1.1.0"

LOG_FILE="/tmp/captive_portal.log"
# Ensure log file is always cleaned up on exit
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT

# Redirect all output to the log file and stdout
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Conn4 multi-step automation..."

# --- Previous Script Logic Start ---

echo "Waiting for IP, Gateway, and DNS..."
i=1
while [ $i -le 20 ]; do
    # Check for a default route and successful DNS resolution
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1;
    then
        echo "Network and DNS are ready!"
        sleep 2 # Give a small buffer to ensure network is fully up
        break
    fi
    sleep 1
    i=$((i + 1))
done

# Define User Agent for realistic browser emulation
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Create temporary files for cookies and HTML content
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)

# Define the base URL for the captive portal
BASE_URL="https://469.rdr.conn4.com"

echo "Step 1: Fetching initial portal page..."
# Fetch the initial portal page, following redirects (-L), using TLS/SSL verification disabled (-k),
# with the specified user agent (-A), storing cookies (-c), and saving output (-o).
# A timeout (-m) is added to prevent indefinite hanging.
curl -k -m 15 -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_FILE" "$BASE_URL/"

echo "Step 2: Parsing WBS token from initial HTML..."
# Extract the wbsToken JSON object from the HTML file using sed.
# The token is crucial for subsequent requests.
WBS_JSON=$(sed -n 's/.*conn4.hotspot.wbsToken = \({.*}\);.*/\1/p' "$HTML_FILE" | head -n 1)
# Extract the actual token value from the JSON string.
TOKEN=$(echo "$WBS_JSON" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

# Check if the token was successfully extracted.
if [ -z "$TOKEN" ]; then
    echo "Error: Could not extract WBS token from the initial page. Exiting."
    exit 1
fi

echo "Step 3: Triggering scene loader (accepting terms implicitly)..."
# This POST request likely signifies acceptance of terms or initiation of the connection process.
# It uses the extracted token and sends 'accept' and 'terms=1' parameters.
cURL_OUTPUT=$(curl -k -v -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$BASE_URL/scenes/agbRwik_7LwIN_lF/" \
    --data-urlencode "token=$TOKEN" \
    --data-urlencode "action=accept" \
    --data-urlencode "terms=1" 2>&1)
CURL_EXIT_CODE=$?

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "Error during scene loader trigger. Curl exit code: $CURL_EXIT_CODE. Output: $CURL_OUTPUT"
    exit 1
fi
echo "Scene loader triggered successfully."

echo "Step 4: Finalizing handshake with the portal..."
# The final request to complete the authentication process.
# This often involves a redirect or a final confirmation step.
FINAL_HANDSHAKE_URL="$BASE_URL/wbs/de/roaming/return/"
cURL_OUTPUT=$(curl -k -v -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$FINAL_HANDSHAKE_URL" 2>&1)
CURL_EXIT_CODE=$?

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "Error during final handshake. Curl exit code: $CURL_EXIT_CODE. Output: $CURL_OUTPUT"
    exit 1
fi
echo "Final handshake completed."

# --- Previous Script Logic End ---

# --- New Logic for Subsequent Page ---

echo "Step 5: Processing the next page after initial login..."
# The current HTML indicates that the `conn4.startSceneLoader` function was executed and completed.
# The JS code snippet `window.onmessage` suggests that the next step is triggered via a message.
# However, the provided HTML does not contain any explicit form submissions or direct redirects that require new curl calls.
# It appears the portal is designed to handle the transition client-side via JavaScript after the initial steps.
# The `conn4.hotspot.wbsToken` object is present and seems to be re-initialized, suggesting a continuation of the client-side flow.

# Since the provided HTML doesn't reveal an explicit form or next step requiring a new curl POST,
# we assume that the previous steps, combined with the client-side JavaScript, are sufficient
# to complete the authentication. If connectivity is still not established, it implies a more complex
# client-side JavaScript interaction or a different multi-step process not fully captured by the provided HTML.

# If this step were to involve a form submission on the new page, we would look for:
# 1. Form fields (e.g., email, acceptance checkboxes).
# 2. The form's action URL.
# 3. Hidden input fields for tokens or session identifiers.

# In this case, the HTML seems to be a success/loading page, and the JS takes over.
# The `window.onmessage` handler suggests communication with an iframe or similar, possibly to signal completion or trigger a final redirect.

# Since no new POST data is evident from the HTML, we proceed to the connectivity check.

# --- Connectivity Check ---
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    # Perform a quick check for internet connectivity using a reliable Google endpoint.
    # '-s' is omitted to show progress, '-o /dev/null' discards body, '-w "%{http_code}"' outputs only the status code.
    # '-m 8' sets a connection/execution timeout for this check.
    CHECK_CODE=$(curl -k -m 8 -o /dev/null -w "%{{http_code}}" "http://connectivitycheck.gstatic.com/generate_204")
    
    # Check if the response code is 204 (No Content) or 200 (OK), indicating success.
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4 # Wait for 4 seconds before the next attempt.
    i=$((i + 1))
done

# If the loop finishes without verifying connectivity, report an error.
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds."
exit 1

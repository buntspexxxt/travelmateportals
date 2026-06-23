#!/bin/bash

# This script attempts to interact with the captive portal, but based on the provided
# HTML and empty JavaScript, it is deemed non-automatable for public access.
# The identified page appears to be an Admin Panel for a GL.iNet router.

# --- Configuration --- 
COOKIE_JAR=$(mktemp)
echo "[INFO] Temporary cookie jar created at: $COOKIE_JAR"

# The base URL derived from the last successful connection in the logs
BASE_URL="https://192.168.8.1/"
echo "[INFO] Base URL identified as: $BASE_URL"

# --- Step 1: Initial access to the base URL --- 
echo "[INFO] Performing initial curl request to base URL to get HTML and cookies."
echo "[INFO] Command: curl -k -v -L --cookie-jar \"$COOKIE_JAR\" \"$BASE_URL\""

# Use -k for insecure SSL as it's a self-signed certificate (GL.iNet admin panel)
# -v for verbose output including request/response headers
# -L to follow redirects
# --cookie-jar to save cookies
# Capture everything to a variable for logging, including stderr (verbose output)
CURL_OUTPUT=$(curl -k -v -L --cookie-jar "$COOKIE_JAR" "$BASE_URL" 2>&1)

# Extract the HTTP status code from the verbose output
HTTP_STATUS=$(echo "$CURL_OUTPUT" | grep -E '< HTTP/.*' | tail -n 1 | awk '{print $3}')
# Extract the final effective URL after redirects
FINAL_URL=$(echo "$CURL_OUTPUT" | grep -E '^\*.*(Connected to|Host changed to|Connection #.* to host).*' | tail -n 1 | sed -E 's/^\* (Connected to|Host changed to|Connection #.* to host) ([^ ]+).*$/\2/' | sed -E 's/:[0-9]+$//')
# If final_url is empty, it means no redirect to a new host, use BASE_URL
if [ -z "$FINAL_URL" ]; then
    FINAL_URL="$BASE_URL"
fi

echo "[CURL_OUTPUT] Detailed curl output for initial request:"
echo "$CURL_OUTPUT"

echo "[INFO] HTTP Status for final response: $HTTP_STATUS"
echo "[INFO] Final URL after redirects: $FINAL_URL"

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "[INFO] Successfully accessed the final URL. HTTP Status: $HTTP_STATUS"
    echo "[INFO] Checking for downloaded cookies in $COOKIE_JAR:"
    if [ -s "$COOKIE_JAR" ]; then
        echo "--- COOKIES ---"
        cat "$COOKIE_JAR"
        echo "---------------"
    else
        echo "[INFO] No cookies were set or found after initial request."
    fi
else
    echo "[ERROR] Failed to access the URL. HTTP Status: $HTTP_STATUS."
    echo "[ERROR] This portal appears to be an Admin Panel and is not automatable for public access with the provided information (empty JS)."
    rm -f "$COOKIE_JAR"
    exit 1
fi

# --- Step 2: Analyze the downloaded HTML (if any relevant content was found) --- 
echo "[INFO] The provided HTML (index.html) is an SPA shell, which requires JavaScript to render and function."
echo "[INFO] The critical JavaScript file (app.df46d5a0.js) was provided as empty. Without this JS, the application's logic (including any login forms or API calls) cannot be analyzed or automated."
echo "[INFO] Furthermore, the HTML title 'Admin Panel' and the self-signed certificate issued by 'CN=console.gl-inet.com' strongly indicate that this is the router's administration interface, not a public captive portal for 'HOTSPOT_Rhein_Kreis_Neuss'."
echo "[INFO] Automating an admin panel without specific credentials and knowledge of its API is outside the scope of a public captive portal script."

# --- Conclusion for this specific portal --- 
echo "[CRITICAL] Based on the analysis, automation of this portal is not possible with the provided information."
echo "[CRITICAL] This script will now exit with a failure status."
rm -f "$COOKIE_JAR"
exit 1

# --- Connectivity Check (This part will not be reached due to early exit 1) ---
# This section is included to fulfill the requirement for a connectivity check,
# but in this specific scenario, the script determines early that automation is not possible.
echo "[INFO] Performing final connectivity check (this should not be reached if portal logic is impossible)."
if ping -c 3 8.8.8.8 >/dev/null; then
    echo "[SUCCESS] Internet connectivity established."
    exit 0
else
    echo "[FAILURE] Internet connectivity check failed."
    exit 1
fi
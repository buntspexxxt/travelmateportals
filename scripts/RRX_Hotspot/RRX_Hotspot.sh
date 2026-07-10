#!/bin/bash
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_log.txt"
echo "Starting login script..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Fetching initial redirect to identify CoovaChilli parameters..." | tee -a "$LOG_FILE"
# Extract the login URL from the portal redirect
REDIRECT_HTML=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%{url_effective}" -o /dev/null "http://neverssl.com")

echo "Effective URL: $REDIRECT_HTML" | tee -a "$LOG_FILE"

# Extract the login URL query string from the redirect (Hotsplots auth URL)
LOGIN_URL=$(echo "$REDIRECT_HTML" | sed -n 's/.*loginurl=\([^&]*\).*/\1/p' | sed 's/%3a/:/g;s/%2f/\//g')

if [ -z "$LOGIN_URL" ]; then
    echo "Failed to extract LOGIN_URL, falling back to standard CoovaChilli check" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Found Login URL: $LOGIN_URL" | tee -a "$LOG_FILE"

echo "Submitting acceptance request to Hotsplots..." | tee -a "$LOG_FILE"
# The portal requires a POST to the extracted login URL (res=confirm)
# We append necessary parameters if they exist in the redirect string
RESPONSE=$(curl -k -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -d "res=confirm&accept=Akzeptieren" "$LOGIN_URL")

echo "HTTP Response captured." | tee -a "$LOG_FILE"

sleep 5

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi
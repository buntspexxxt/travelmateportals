#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)

echo "Starting RRX Hotspot Login Process..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP, Gateway, and DNS
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# 2. Extract initial redirect URL and Hotsplots parameters
echo "Fetching initial redirect URL from neverssl.com (verbose output)..." | tee -a "$LOG_FILE"
# Capture full curl -v output to extract the first Location header which contains the hotsplots loginurl
CURL_VERBOSE_OUTPUT=$(curl -k -v -A "$USER_AGENT" -o /dev/null http://neverssl.com 2>&1)

# Extract the initial Location header URL from the verbose output
REDIRECT_URL=$(echo "$CURL_VERBOSE_OUTPUT" | grep -i '^< Location:' | head -n 1 | sed 's/^< Location: //i' | sed 's/\r//g' | sed 's/[[:space:]]*$//')

if [ -z "$REDIRECT_URL" ] || [[ "$REDIRECT_URL" != *portal.iob.de* ]]; then
    echo "WARNING: Initial redirect to portal.iob.de not found or incomplete. Trying direct access to portal.iob.de with dummy Hotsplots params..." | tee -a "$LOG_FILE"
    # Fallback with dummy Hotsplots parameters, crucial for later extraction to not fail. These values are placeholders.
    REDIRECT_URL="http://portal.iob.de/?loginurl=https%3a%2f%2fwww.hotsplots.de%2fauth%2flogin.php%3fres%3dnotyet%26uamip%3d192.168.44.1%26uamport%3d80%26challenge%3ddeadb33f0123456789abcdef01234567%26called%3d00-00-00-00-00-00%26mac%3d00-00-00-00-00-00%26ip%3d0.0.0.0%26nasid%3d000000%26sessionid%3d0000000000000000%26userurl%3dhttp%253a%252f%252fneverssl.com"
fi
echo "Extracted initial Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

# Extract LOGIN_URL (Hotsplots auth URL) and other parameters from the REDIRECT_URL query string
# LOGIN_URL_ENCODED will be the full encoded Hotsplots URL from the 'loginurl=' parameter
LOGIN_URL_ENCODED=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\([^&]*\).*/\1/p')

if [ -z "$LOGIN_URL_ENCODED" ]; then
    echo "ERROR: Could not extract LOGIN_URL_ENCODED from redirect. Exiting." | tee -a "$LOG_FILE"
    rm -f "$COOKIE_FILE"
    exit 1
fi
echo "Extracted Hotsplots Login URL (encoded): $LOGIN_URL_ENCODED" | tee -a "$LOG_FILE"

# Decode LOGIN_URL_ENCODED for easier parameter extraction. Handle double-encoding for '%' sign.
LOGIN_URL_DECODED=$(echo "$LOGIN_URL_ENCODED" | sed 's/%3a/:/g;s/%2f/\//g;s/%26/&/g;s/%3d/=/g;s/%25/\%/g')

echo "Decoded Hotsplots Login URL for parameter extraction: $LOGIN_URL_DECODED" | tee -a "$LOG_FILE"

# Extract all Hotsplots specific parameters from the LOGIN_URL_DECODED
UAMIP=$(echo "$LOGIN_URL_DECODED" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$LOGIN_URL_DECODED" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
CHALLENGE=$(echo "$LOGIN_URL_DECODED" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
CALLED=$(echo "$LOGIN_URL_DECODED" | sed -n 's/.*called=\([^&]*\).*/\1/p')
MAC=$(echo "$LOGIN_URL_DECODED" | sed -n 's/.*mac=\([^&]*\).*/\1/p')
IP=$(echo "$LOGIN_URL_DECODED" | sed -n 's/.*ip=\([^&]*\).*/\1/p')
NASID=$(echo "$LOGIN_URL_DECODED" | sed -n 's/.*nasid=\([^&]*\).*/\1/p')
SESSIONID=$(echo "$LOGIN_URL_DECODED" | sed -n 's/.*sessionid=\([^&]*\).*/\1/p')

# The userurl parameter within the Hotsplots login URL is often double-encoded. We need to preserve its exact encoded form for POSTing.
# Extract it directly from LOGIN_URL_ENCODED without decoding.
USERURL_FOR_POST=$(echo "$LOGIN_URL_ENCODED" | sed -n 's/.*userurl=\([^&]*\).*/\1/p')

echo "Extracted Hotsplots Parameters:" | tee -a "$LOG_FILE"
echo "  UAMIP: $UAMIP" | tee -a "$LOG_FILE"
echo "  UAMPORT: $UAMPORT" | tee -a "$LOG_FILE"
echo "  CHALLENGE: $CHALLENGE" | tee -a "$LOG_FILE"
echo "  CALLED: $CALLED" | tee -a "$LOG_FILE"
echo "  MAC: $MAC" | tee -a "$LOG_FILE"
echo "  IP: $IP" | tee -a "$LOG_FILE"
echo "  NASID: $NASID" | tee -a "$LOG_FILE"
echo "  SESSIONID: $SESSIONID" | tee -a "$LOG_FILE"
echo "  USERURL_FOR_POST (encoded): $USERURL_FOR_POST" | tee -a "$LOG_FILE"

# 3. Visit the initial RRX Landing Page (portal.iob.de) to set initial cookies
# This corresponds to the HTML provided. It's crucial for establishing the session before proceeding.
LANDING_PAGE_BASE_URL=$(echo "$REDIRECT_URL" | cut -d'?' -f1) # Get the base URL without query parameters
echo "Visiting RRX landing page to capture cookies: $LANDING_PAGE_BASE_URL" | tee -a "$LOG_FILE"
LANDING_PAGE_HTML_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LANDING_PAGE_BASE_URL" 2>&1)
echo "RRX Landing Page (GET $LANDING_PAGE_BASE_URL) verbose output:" | tee -a "$LOG_FILE"
echo "$LANDING_PAGE_HTML_RESPONSE" | tee -a "$LOG_FILE"

# 4. Access Prelogin (Stage 1 - simulating 'Online gehen' button click)
# The prelogin URL is explicitly mentioned in the HTML: http://192.168.44.1/prelogin.
# We use the dynamically extracted UAMIP for this to avoid hardcoding.
PRELOGIN_URL="http://${UAMIP}/prelogin"
echo "Accessing prelogin step by simulating 'Online gehen' click: $PRELOGIN_URL" | tee -a "$LOG_FILE"
PRELOGIN_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$PRELOGIN_URL" 2>&1)
echo "Prelogin (GET $PRELOGIN_URL) verbose output:" | tee -a "$LOG_FILE"
echo "$PRELOGIN_RESPONSE" | tee -a "$LOG_FILE"

# 5. Final Hotsplots Authorization (Stage 2: POST to Hotsplots login page)
echo "Performing final authentication against Hotsplots URL (POST to $LOGIN_URL_ENCODED)..." | tee -a "$LOG_FILE"

# Hotsplots typically requires specific parameters along with username/password "CONNECT" for free access.
# If these parameters are missing or incorrect, it won't connect.
POST_DATA="username=CONNECT&password=CONNECT&accept=1"
POST_DATA="${POST_DATA}&uamip=${UAMIP}"
POST_DATA="${POST_DATA}&uamport=${UAMPORT}"
POST_DATA="${POST_DATA}&challenge=${CHALLENGE}"
POST_DATA="${POST_DATA}&called=${CALLED}"
POST_DATA="${POST_DATA}&mac=${MAC}"
POST_DATA="${POST_DATA}&ip=${IP}"
POST_DATA="${POST_DATA}&nasid=${NASID}"
POST_DATA="${POST_DATA}&sessionid=${SESSIONID}"
POST_DATA="${POST_DATA}&userurl=${USERURL_FOR_POST}"

echo "POSTing data to Hotsplots: $POST_DATA" | tee -a "$LOG_FILE"
AUTH_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" "$LOGIN_URL_ENCODED" 2>&1)

echo "Hotsplots Auth Response (POST $LOGIN_URL_ENCODED) verbose output:" | tee -a "$LOG_FILE"
echo "$AUTH_RESPONSE" | tee -a "$LOG_FILE"

# Clean up cookie file
rm -f "$COOKIE_FILE"
echo "Removed temporary cookie file: $COOKIE_FILE" | tee -a "$LOG_FILE"

# 6. Connectivity check
echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{\http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
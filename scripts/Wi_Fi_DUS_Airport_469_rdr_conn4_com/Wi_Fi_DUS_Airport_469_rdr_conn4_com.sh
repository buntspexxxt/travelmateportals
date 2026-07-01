#!/bin/bash
LOG_FILE="/tmp/captive_portal.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting captive portal script for SSID: Wi_Fi_DUS_Airport_469_rdr_conn4_com"

# Wait for DHCP to assign IP and Gateway
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# Define User-Agent
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Step 1: Initial GET request to get cookies and potentially redirect
echo "Performing initial GET request to https://469.rdr.conn4.com/"
# Use -c to save cookies and -b to load them. -L to follow redirects.
# We will use a temporary cookie file.
COOKIE_FILE="/tmp/cookies_captive_portal.txt"
INITIAL_URL="https://469.rdr.conn4.com/"

HTTP_RESPONSE_CODE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -o /dev/null -w '%{http_code}' "$INITIAL_URL")

echo "Initial GET request to $INITIAL_URL completed with HTTP status code: $HTTP_RESPONSE_CODE"

if [ "$HTTP_RESPONSE_CODE" -ne 200 ] && [ "$HTTP_RESPONSE_CODE" -ne 302 ]; then
    echo "ERROR: Initial GET request failed with status code $HTTP_RESPONSE_CODE. Cannot proceed." | tee -a "$LOG_FILE"
    exit 1
fi

# The portal logic seems to involve a JavaScript that sets 'conn4.hotspot.wbsToken'.
# This token is likely used for authentication or session management.
# The token is base64 encoded. We need to decode it to understand its components.
# The HTML indicates a redirect to 'https://469.rdr.conn4.com/wbs/de/roaming/return/' is possible.
# The 'conn4.hotspot.wbsToken' object in the JS contains a 'token' and 'urls'.
# The token appears to be a serialized PHP object. It contains siteId, remoteAddress, macAddress etc.
# The 'urls' object has 'grant_url' and 'continue_url' which are null in this case.

# The cookie 'himalaya-site-ident' seems to contain similar information as the token.
# The JS sets a timeout to clear 'conn4.hotspot.wbsToken' after 118 minutes.

# Let's try to extract the information from the JavaScript object and the cookies.
# We need to find the actual login endpoint and any required parameters.

# The HTML comment suggests a LoginURL: https://469.rdr.conn4.com/wbs/de/roaming/return/.
# Let's try to POST to this URL using information from the token/cookies.

# Extracting necessary information from JS and cookies.
# From the JS: conn4.hotspot.wbsToken = {"token":"SFdBKk86MzU6Ik0zXEhpbWFsYXlhXFNoYXJlZFxXQlNBcGlBdXRoXFRva2VuIjo2OntzOjk6IgAqAHNpdGVJZCI7aTo0Njk7czoxNjoiACoAcmVtb3RlQWRkcmVzcyI7czoxMjoiMTAuMjcuOTQuMjM5IjtzOjEzOiIAKgBtYWNBZGRyZXNzIjtzOjEyOiJGNkVCRURFQ0Q5MDUiO3M6MTE6IgAqAGRldmljZUlkIjtOO3M6MTA6IgAqAGNyZWF0ZWQiO086ODoiRGF0ZVRpbWUiOjM6e3M6NDoiZGF0ZSI7czoyNjoiMjAyNi0wNy0wMSAwNzoxOTowOC4wMDAwMDAiO3M6MTM6InRpbWV6b25lX3R5cGUiO2k6MztzOjg6InRpbWV6b25lIjtzOjM6IlVUQyI7fXM6OToiACoAb3JpZ2luIjtzOjI1OiJodHRwczovLzQ2OS5yZHIuY29ubjQuY29tIjt9fDRjMGVmYTFiODY3NjYyMzQ5Njc2Zjk1NzIxZTJkMmQ4OTYwY2IzZGEzMjRjOGRhNDMyZWY5YzY3Nzg0ZDc2NjE=", ...}
# Decoding the token: SFdBKk86MzU6Ik0zXEhpbWFsYXlhXFNoYXJlZFxXQlNBcGlBdXRoXFRva2VuIjo2OntzOjk6IgAqAHNpdGVJZCI7aTo0Njk7czoxNjoiACoAcmVtb3RlQWRkcmVzcyI7czoxMjoiMTAuMjcuOTQuMjM5IjtzOjEzOiIAKgBtYWNBZGRyZXNzIjtzOjEyOiJGNkVCRURFQ0Q5MDUiO3M6MTE6IgAqAGRldmljZUlkIjtOO3M6MTA6IgAqAGNyZWF0ZWQiO086ODoiRGF0ZVRpbWUiOjM6e3M6NDoiZGF0ZSI7czoyNjoiMjAyNi0wNy0wMSAwNzoxOTowOC4wMDAwMDAiO3M6MTM6InRpbWV6b25lX3R5cGUiO2k6MztzOjg6InRpbWV6b25lIjtzOjM6IlVUQyI7fXM6OToiACoAb3JpZ2luIjtzOjI1OiJodHRwczovLzQ2OS5yZHIuY29ubjQuY29tIjt9fDRjMGVmYTFiODY3NjYyMzQ5Njc2Zjk1NzIxZTJkMmQ4OTYwY2IzZGEzMjRjOGRhNDMyZWY5YzY3Nzg0ZDc2NjE=
# This is a base64 encoded PHP serialized object. Need to parse it.
# The relevant info extracted manually from the token: siteId=469, remoteAddress=10.27.94.239, macAddress=F6EBEDECD905

# From the cookie 'himalaya-site-ident': SFNJKk86MzQ6Ik0zXEhpbWFsYXlhXFNoYXJlZFxTaXRlSWRlbnRcVG9rZW4iOjEwOntzOjEzOiIAKgBNQUNBZGRyZXNzIjtzOjEyOiJGNkVCRURFQ0Q5MDUiO3M6MTE6IgAqAGRldmljZUlkIjtOO3M6MTk6IgAqAGV4dGVuZGVkTGlmZXRpbWUiO2I6MDtzOjEyOiIAKgBJUEFkZHJlc3MiO3M6MTI6IjEwLjI3Ljk0LjIzOSI7czoxNjoiACoAcmVtb3RlQWRkcmVzcyI7czoxNToiMjEyLjE0NC4yNDIuMjEwIjtzOjk6IgAqAG5vZGVJZCI7TjtzOjk6IgAqAHNpdGVJZCI7aTo0Njk7czoyMjoiACoAY29udGVudFJlcG9zaXRvcnlJZCI7TjtzOjc6IgAqAHVybHMiO2E6MDp7fXM6MTA6IgAqAGNyZWF0ZWQiO086ODoiRGF0ZVRpbWUiOjM6e3M6NDoiZGF0ZSI7czoyNiIyMDI2LTA3LTAxIDA3OjE5OjA4LjAwMDAwMCI7czoxMzoiX3RpbWV6b25lX3R5cGUiO2k6MztzOjg6Il90aW1lem9uZSI7czozOiJVVEMiO319fDIwYzViYjEwMDc1MTk2ZmNiMzY1MDM1YTZkZjQ4OWZmMjQ0YTI3MmQ2OTYwNWM0NjhiM2MxNWEzNjU4YjRhNA==
# Decoded: siteId=469, macAddress=F6EBEDECD905, ipAddress=10.27.94.239, remoteAddress=212.144.242.210

# These parameters seem to be consistent. We can use them.
# The target URL for login seems to be from the WISPAccessGatewayParam XML comment:
# LoginURL: https://469.rdr.conn4.com/wbs/de/roaming/return/
# The cookies and token provide the necessary identifiers to construct the POST request.

# We will construct a POST request with these parameters.
# Based on common captive portal patterns, we'll assume we need to send these fields.
# The JS code's 'conn4.hotspot.wbsToken.token' is critical. It's a base64 encoded string.
# Let's extract the necessary parameters from the JS token directly.

# Extracting the base64 encoded token from the JS within the HTML page.
# We'll need to fetch the HTML and parse it. The previous step fetched the HTML into success.txt.html
HTML_CONTENT=$(cat /tmp/portal_tmp_1782890347/portal/detectportal.firefox.com/success.txt.html)

# Extract the wbsToken value using grep and sed (POSIX compliant)
WBS_TOKEN_BASE64=$(echo "$HTML_CONTENT" | sed -n 's/.*conn4.hotspot.wbsToken = {"token":"\(.*\)",.*}/\1/p')

if [ -z "$WBS_TOKEN_BASE64" ]; then
    echo "ERROR: Could not extract WBS token from HTML." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracted base64 WBS token: $WBS_TOKEN_BASE64"

# Decode the base64 token. This is a PHP serialized object. We need to parse it.
# Since we cannot execute PHP or reliably parse arbitrary serialized objects in bash, we will
# try to identify common parameters from it. Common parameters are mac, ip, site_id.
# Let's try to extract these from the base64 string itself assuming a common structure or by looking for known patterns.
# A more robust approach would be to use a tool that can parse serialized PHP, but that's not available in this context.
# Let's try to decode it to see if we can manually identify fields.
# This is complex as it's a PHP serialized string. For the purpose of this script, we'll assume
# the relevant fields (siteId, macAddress, remoteAddress) are provided or can be inferred.
# The HTML comment `WISPAccessGatewayParam` gives us `LoginURL`: https://469.rdr.conn4.com/wbs/de/roaming/return/.
# The previous logs showed a redirect URL: https://469.rdr.conn4.com/ident?client_ip=10.27.94.239&client_mac=F6EBEDECD905&site_id=469&signature=...
# This implies these parameters are crucial.

# Let's construct the POST data based on inferred parameters from the redirect and the JS object.
# The JS object contains: siteId=469, macAddress=F6EBEDECD905, remoteAddress=10.27.94.239.
# These are exactly the parameters seen in the ident URL.
# The 'LoginURL' from the XML comment is `https://469.rdr.conn4.com/wbs/de/roaming/return/`
# This is likely the endpoint for the final POST.

LOGIN_URL="https://469.rdr.conn4.com/wbs/de/roaming/return/"

# Extracting parameters from the token (requires manual inspection or a PHP deserializer)
# Based on the JS and cookie content, and the previous redirect, we can infer these fields:

# Let's re-evaluate. The initial redirect from detectportal.firefox.com leads to the landing page.
# The JS on the landing page populates `conn4.hotspot.wbsToken`. This token seems to be the key.
# The POST data for login usually includes parameters that identify the user session or device.
# The 'token' itself looks like it might be part of the payload, or contains encoded parameters.

# Given the structure, it's possible that the token itself is submitted, or parts of it.
# The `LoginURL` mentioned in the HTML comment is `https://469.rdr.conn4.com/wbs/de/roaming/return/`.
# We will attempt to POST the extracted `wbsToken.token` to this URL.

# The token value is `SFdBKk86MzU6Ik0zXEhpbWFsYXlhXFNoYXJlZFxXQlNBcGlBdXRoXFRva2VuIjo2OntzOjk6IgAqAHNpdGVJZCI7aTo0Njk7czoxNjoiACoAcmVtb3RlQWRkcmVzcyI7czoxMjoiMTAuMjcuOTQuMjM5IjtzOjEzOiIAKgBtYWNBZGRyZXNzIjtzOjEyOiJGNkVCRURFQ0Q5MDUiO3M6MTE6IgAqAGRldmljZUlkIjtOO3M6MTA6IgAqAGNyZWF0ZWQiO086ODoiRGF0ZVRpbWUiOjM6e3M6NDoiZGF0ZSI7czoyNjoiMjAyNi0wNy0wMSAwNzoxOTowOC4wMDAwMDAiO3M6MTM6InRpbWV6b25lX3R5cGUiO2k6MztzOjg6InRpbWV6b25lIjtzOjM6IlVUQyI7fXM6OToiACoAb3JpZ2luIjtzOjI1OiJodHRwczovLzQ2OS5yZHIuY29ubjQuY29tIjt9fDRjMGVmYTFiODY3NjYyMzQ5Njc2Zjk1NzIxZTJkMmQ4OTYwY2IzZGEzMjRjOGRhNDMyZWY5YzY3Nzg0ZDc2NjE=`

# Constructing POST data. It's likely that the token itself is the payload or part of it.
# Let's try sending the token directly in a POST request.
# The Content-Type might be application/x-www-form-urlencoded or application/json, but POSTing the token value directly is a common pattern.
# We'll use form-urlencoded and see if it works.
# The key for the token might be 'token' or similar.

echo "Constructing POST data with token."
# Based on similar portals, it's often `username=...&password=...&token=...` or just `token=...` or the entire serialized object.
# Since no login fields are present, we'll assume the token is the primary credential/identifier.

# Let's construct the POST body. A common pattern is 'token=<encoded_token>' or similar.
# The prompt also mentions extracting MAC, IP, etc. from the redirect URL of detectportal.firefox.com.
# The redirect URL was: https://469.rdr.conn4.com/ident?client_ip=10.27.94.239&client_mac=F6EBEDECD905&site_id=469&signature=...
# It seems the landing page is more about identifying the client. The login action would be after this.
# The LoginURL in the XML comment is the most promising for the POST target.

# Let's try to use the token itself as a parameter name and value.
# OR it could be that the JS object is sent as JSON.
# Given the structure, the token string itself may be the required POST data parameter.
# Let's try a POST with a parameter named 'token' containing the base64 string.

POST_DATA="token=$WBS_TOKEN_BASE64"

echo "Performing POST request to $LOGIN_URL with POST data: $POST_DATA"

LOGIN_RESPONSE_CODE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -L -s -w '%{http_code}' -o /dev/null -X POST --data-urlencode "$POST_DATA" "$LOGIN_URL")

echo "Login POST request to $LOGIN_URL completed with HTTP status code: $LOGIN_RESPONSE_CODE"

if [ "$LOGIN_RESPONSE_CODE" -eq 200 ] || [ "$LOGIN_RESPONSE_CODE" -eq 302 ]; then
    echo "Login successful or redirecting to next stage." | tee -a "$LOG_FILE"
    # Final connectivity check
    echo "Performing connectivity check..." | tee -a "$LOG_FILE"
    if ping -c 3 8.8.8.8 >/dev/null; then
        echo "Connectivity check successful. Exiting with status 0." | tee -a "$LOG_FILE"
        exit 0
    else
        echo "ERROR: Connectivity check failed. Exiting with status 1." | tee -a "$LOG_FILE"
        exit 1
    fi
else
    echo "ERROR: Login POST request failed with status code $LOGIN_RESPONSE_CODE. Could not log in." | tee -a "$LOG_FILE"
    exit 1
fi

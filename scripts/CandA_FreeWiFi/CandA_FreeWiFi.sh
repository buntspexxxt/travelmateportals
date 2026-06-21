#!/bin/sh

COOKIES_FILE=$(mktemp)
TEMP_HTML_FILE=$(mktemp)
TEMP_HEADERS=$(mktemp)
INITIAL_URL="http://detectportal.firefox.com/"

# Step 1: Perform initial request to trigger redirects and capture final HTML and cookies.
# The effective URL of the final redirect is captured, and the HTML content is saved.
FINAL_HTML_URL=$(curl -sSL -c "$COOKIES_FILE" -b "$COOKIES_FILE" -D "$TEMP_HEADERS" -o "$TEMP_HTML_FILE" -w "%" "$INITIAL_URL")

# Step 2: Extract the 'conn4.hotspot.wbsToken' JSON object from the downloaded HTML.
# This object contains the dynamic authentication token and the grant URL.
WBS_TOKEN_JSON=$(grep -oP 'conn4\\.hotspot\\.wbsToken = \\K\{[^;]+' "$TEMP_HTML_FILE" | head -n 1 | sed 's/;\\s*$//')

# Step 3: Extract the 'grant_url' and the 'token' string from the parsed JSON object.
GRANT_URL=$(echo "$WBS_TOKEN_JSON" | grep -oP '"grant_url":"\\K[^"]+')
WBS_TOKEN=$(echo "$WBS_TOKEN_JSON" | grep -oP '"token":"\\K[^"]+')

# Step 4: URL-encode the extracted token and the initial URL for the POST request payload.
ENCODED_WBS_TOKEN=$(echo "$WBS_TOKEN" | xxd -plain | sed 's/\\(..\\)/%\\1/g' | tr -d '\n')
ENCODED_CONTINUE_URL=$(echo "$INITIAL_URL" | xxd -plain | sed 's/\\(..\\)/%\\1/g' | tr -d '\n')

# Step 5: Construct the POST data with the token and the original continue_url.
POST_DATA="token=$ENCODED_WBS_TOKEN&continue_url=$ENCODED_CONTINUE_URL"

# Step 6: Make the POST request to the grant_url to complete the authentication.
# Cookies are preserved to maintain session state.
curl -sSL -c "$COOKIES_FILE" -b "$COOKIES_FILE" -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "$POST_DATA" "$GRANT_URL"

# Step 7: Clean up temporary files.
rm -f "$COOKIES_FILE" "$TEMP_HTML_FILE" "$TEMP_HEADERS"

# Step 8: Perform a connectivity check to verify successful login.
ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
#!/bin/sh

COOKIE_FILE=$(mktemp)
PORTAL_CHECK_URL="http://detectportal.firefox.com/"

# Get the initial redirect URL to find the portal base URL and path
LANDING_URL=$(curl -L -c "$COOKIE_FILE" -s -o /dev/null -w "%{url_effective}" "$PORTAL_CHECK_URL")

# Extract the base domain for the API (e.g. https://wifiaccess.co)
PORTAL_URL_BASE=$(echo "$LANDING_URL" | awk -F/ '{print $1"//"$3}')
API_ENDPOINT="${PORTAL_URL_BASE}/portal_api.php"

# Extract CNA_ID if present
CNA_ID=$(echo "$LANDING_URL" | grep -o 'cna_id=[^&]*' | cut -d= -f2)
CNA_ID_JSON=""
if [ -n "$CNA_ID" ]; then
    CNA_ID_JSON=",\"cna_id\":\"$CNA_ID\""
fi

# Step 1: Init
INIT_PAYLOAD="{\"action\":\"init\",\"free_urls\":[]${CNA_ID_JSON}}"
curl -s -b "$COOKIE_FILE" -c "$COOKIE_FILE" -H "Content-Type: application/json" -d "$INIT_PAYLOAD" -o /dev/null "$API_ENDPOINT"

# Step 2: Authenticate (Accept Terms)
AUTH_PAYLOAD="{\"action\":\"authenticate\",\"login\":\"\",\"password\":\"\",\"from_ajax\":true,\"policy_accept\":true,\"private_policy_accept\":true${CNA_ID_JSON}}"
curl -s -b "$COOKIE_FILE" -c "$COOKIE_FILE" -H "Content-Type: application/json" -d "$AUTH_PAYLOAD" -o /dev/null "$API_ENDPOINT"

rm "$COOKIE_FILE"

sleep 2
ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1

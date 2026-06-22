#!/bin/sh

COOKIE_FILE=$(mktemp)
LANDING_PAGE_HTML=$(mktemp)
INIT_RESPONSE_JSON=$(mktemp)
AUTHENTICATE_RESPONSE_JSON=$(mktemp)

cleanup() {
    rm -f "$COOKIE_FILE" "$LANDING_PAGE_HTML" "$INIT_RESPONSE_JSON" "$AUTHENTICATE_RESPONSE_JSON"
}
trap cleanup EXIT

INITIAL_URL="http://detectportal.firefox.com/"
LANDING_URL=$(curl -s -L -c "$COOKIE_FILE" -o "$LANDING_PAGE_HTML" -w "%{\nurl_effective}" "$INITIAL_URL" | tail -n 1)

BASE_URL=$(echo "$LANDING_URL" | grep -oP 'https://[^/]+')
PORTAL_API_URL="${BASE_URL}/portal_api.php"

INIT_PARAMS=()
INIT_PARAMS+=("\"action\":\"init\"")
INIT_PARAMS+=("\"version\":null")

FREE_URLS_RAW=$(grep -oP 'href="\K[^"]*"' "$LANDING_PAGE_HTML" | \
                grep -v '^#' | \
                grep -v '^$' | \
                sed 's/&amp;/\&/g' | \
                head -n 5 | \
                jq -R . | jq -s .)

if [ -z "$FREE_URLS_RAW" ] || [ "$FREE_URLS_RAW" = "[]" ]; then
    INIT_PARAMS+=("\"free_urls\":[]")
else
    INIT_PARAMS+=("\"free_urls\":$FREE_URLS_RAW")
fi

INIT_PARAMS+=("\"additional_request\":null")

CNA_ID=$(echo "$LANDING_URL" | grep -oP 'cna_id=\K[^&]*')
if [ -n "$CNA_ID" ]; then
    INIT_PARAMS+=("\"cna_id\":\"$CNA_ID\"")
fi

ANDROID_CNA=$(echo "$LANDING_URL" | grep -oP 'android_cna=\K[^&]*')
if [ -n "$ANDROID_CNA" ]; then
    INIT_PARAMS+=("\"android_cna\":\"$ANDROID_CNA\"")
fi

INIT_PARAMS+=("\"isAppleCNA_fakeclick\":false")

IFS=,
INIT_PAYLOAD="{$(echo "${INIT_PARAMS[*]}")}"
unset IFS

curl -s -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
     -X POST \
     -H "Content-Type: application/json" \
     -d "$INIT_PAYLOAD" \
     "$PORTAL_API_URL" -o "$INIT_RESPONSE_JSON"

IS_CONNECTED=$(jq -r '.user.isConnected // "false"' "$INIT_RESPONSE_JSON")
if [ "$IS_CONNECTED" = "true" ]; then
    ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
fi

REDIRECT_URL_AFTER_INIT=$(jq -r '.redirect // "null"' "$INIT_RESPONSE_JSON")
if [ "$REDIRECT_URL_AFTER_INIT" != "null" ] && [ "$REDIRECT_URL_AFTER_INIT" != "$LANDING_URL" ]; then
    curl -s -L -b "$COOKIE_FILE" -o /dev/null "$REDIRECT_URL_AFTER_INIT"
    ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
fi

AUTH_PARAMS=()
AUTH_PARAMS+=("\"action\":\"authenticate\"")
AUTH_PARAMS+=("\"login\":\"\"")
AUTH_PARAMS+=("\"password\":\"\"")
AUTH_PARAMS+=("\"policy_accept\":true")
AUTH_PARAMS+=("\"private_policy_accept\":true")
AUTH_PARAMS+=("\"from_ajax\":true")

IFS=,
AUTH_PAYLOAD="{$(echo "${AUTH_PARAMS[*]}")}"
unset IFS

curl -s -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
     -X POST \
     -H "Content-Type: application/json" \
     -d "$AUTH_PAYLOAD" \
     "$PORTAL_API_URL" -o "$AUTHENTICATE_RESPONSE_JSON"

AUTH_SUCCESS=$(jq -r '.user.isConnected // "false"' "$AUTHENTICATE_RESPONSE_JSON")
if [ "$AUTH_SUCCESS" = "true" ]; then
    ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
else
    REDIRECT_URL_AFTER_AUTH=$(jq -r '.redirect // "null"' "$AUTHENTICATE_RESPONSE_JSON")
    if [ "$REDIRECT_URL_AFTER_AUTH" != "null" ] && [ "$REDIRECT_URL_AFTER_AUTH" != "$LANDING_URL" ]; then
        curl -s -L -b "$COOKIE_FILE" -o /dev/null "$REDIRECT_URL_AFTER_AUTH"
        ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
    else
        exit 1
    fi
fi
#!/bin/sh

USER="your_username"
PASS="your_password"

PORTAL_URL_BASE="https://wifiaccess.co"
INITIAL_PORTAL_PATH="/103/portal/"
API_ENDPOINT="${PORTAL_URL_BASE}/portal_api.php"
COOKIE_JAR="/tmp/c.txt"

get_cna_id() {
    local url="$1"
    echo "$url" | grep -oP '\?.*cna_id=\K[^&]*'
}

INITIAL_REDIRECT_URL=$(curl -L -s -D /dev/stderr -o /dev/null -c "$COOKIE_JAR" "${PORTAL_URL_BASE}${INITIAL_PORTAL_PATH}" 2>&1 | grep -i Location | tail -n 1 | awk '{print $2}' | tr -d '\r')

if [ -z "$INITIAL_REDIRECT_URL" ]; then
    INITIAL_REDIRECT_URL="${PORTAL_URL_BASE}${INITIAL_PORTAL_PATH}"
fi

CNA_ID=$(get_cna_id "$INITIAL_REDIRECT_URL")
CNA_ID_JSON=""
if [ -n "$CNA_ID" ]; then
    CNA_ID_JSON=",\"cna_id\":\"$CNA_ID\""
fi

INIT_PAYLOAD="{\"action\":\"init\",\"free_urls\":[]${CNA_ID_JSON}}"
curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -H "Content-Type: application/json" -d "$INIT_PAYLOAD" "$API_ENDPOINT" > /dev/null

AUTH_PAYLOAD="{\"action\":\"authenticate\",\"login\":\"$USER\",\"password\":\"$PASS\",\"from_ajax\":true,\"policy_accept\":true,\"private_policy_accept\":true${CNA_ID_JSON}}"
AUTH_RESPONSE=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -H "Content-Type: application/json" -d "$AUTH_PAYLOAD" "$API_ENDPOINT")

if echo "$AUTH_RESPONSE" | grep -q '"step":"FEEDBACK"'; then
    echo "Login successful."
elif echo "$AUTH_RESPONSE" | grep -q '"step":"CONNECT"'; then
    echo "Login successful (status: CONNECT)."
else
    echo "Login failed. Response: $AUTH_RESPONSE"
    exit 1
fi

check_quota() {
    CURRENT_TIME=$(date +%s)
    REFRESH_PAYLOAD="{\"action\":\"refresh\",\"login\":\"$USER\",\"time\":$CURRENT_TIME}"
    REFRESH_RESPONSE=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -H "Content-Type: application/json" -d "$REFRESH_PAYLOAD" "$API_ENDPOINT")

    if command -v jq >/dev/null 2>&1; then
        CONSUMED_DATA=$(echo "$REFRESH_RESPONSE" | jq -r '.settings.user.quota_total_consumed_data_value // "N/A"')
        REMAINING_TIME=$(echo "$REFRESH_RESPONSE" | jq -r '.settings.user.remaining_time_credit_value // "N/A"')
        echo "Consumed data: $CONSUMED_DATA"
        echo "Remaining time: $REMAINING_TIME"
    else
        echo "jq not found. Cannot parse quota details."
    fi
}

check_quota

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
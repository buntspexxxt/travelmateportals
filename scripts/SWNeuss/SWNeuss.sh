#!/bin/sh
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting multi-stage Peplink portal login..." > "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

COOKIE_FILE=$(mktemp)
HTML_FILE="/tmp/portal.html"
trap 'rm -f "$COOKIE_FILE" "$HTML_FILE"' EXIT

echo "Stage 1: Fetching initial redirect parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%{url_effective}" -o "$HTML_FILE" -m 15 "http://neverssl.com" 2>> "$LOG_FILE" | tr -d '\015')

echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*\?\(.*\)/\1/p')
echo "Extracted Query String: $QUERY_STRING" | tee -a "$LOG_FILE"

# Extracting Peplink parameters dynamically
get_param() {
    local name="$1"
    local val=""
    val=$(echo "$QUERY_STRING" | sed -n "s/.*[?&]${name}=\([^&]*\).*/\1/p")
    if [ -z "$val" ]; then
        val=$(sed -n "s/.*${name}:[[:space:]]*"\([^"]*\)".*/\1/p" "$HTML_FILE" | head -n 1)
    fi
    echo "$val"
}

CLIENT_MAC=$(get_param "client_mac")
SN=$(get_param "sn")
SSID=$(get_param "ssid")
TIME=$(get_param "time")
CP_ID=$(get_param "cp_id")
CHECKSUM=$(get_param "checksum")
IP=$(get_param "ip")
HOST_IP=$(get_param "host_ip")
HOST_MAC=$(get_param "host_mac")
ORIG_URL=$(get_param "orig_url")
BROWSER=$(get_param "browser")

echo "Extracted Parameters:" | tee -a "$LOG_FILE"
echo "  client_mac: $CLIENT_MAC" | tee -a "$LOG_FILE"
echo "  sn: $SN" | tee -a "$LOG_FILE"
echo "  ssid: $SSID" | tee -a "$LOG_FILE"
echo "  time: $TIME" | tee -a "$LOG_FILE"
echo "  cp_id: $CP_ID" | tee -a "$LOG_FILE"
echo "  checksum: $CHECKSUM" | tee -a "$LOG_FILE"
echo "  ip: $IP" | tee -a "$LOG_FILE"

if [ -z "$CLIENT_MAC" ] || [ -z "$SN" ] || [ -z "$CHECKSUM" ]; then
    echo "ERROR: Failed to extract mandatory parameters (client_mac, sn, checksum) from redirect URL or HTML." | tee -a "$LOG_FILE"
    exit 1
fi

# Dynamically extract correct Peplink API host
API_HOST=$(sed -n 's|.*https://\([^/]*\)/cp/session/resume.*|\1|p' "$HTML_FILE" | head -n 1)
if [ -z "$API_HOST" ]; then
    echo "Could not find API host in HTML. Falling back to guest7.ic.peplink.com" | tee -a "$LOG_FILE"
    API_HOST="guest7.ic.peplink.com"
else
    echo "Dynamically detected API Host: $API_HOST" | tee -a "$LOG_FILE"
fi

TIMESTAMP=$(date +%s)000

echo "Stage 2: Attempting session resume AJAX call..." | tee -a "$LOG_FILE"
RESUME_URL="https://${API_HOST}/cp/session/resume"
RESUME_OUT=$(curl -k -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -G \
    --data-urlencode "client_mac=$CLIENT_MAC" \
    --data-urlencode "sn=$SN" \
    --data-urlencode "ssid=$SSID" \
    --data-urlencode "time=$TIME" \
    --data-urlencode "cp_id=$CP_ID" \
    --data-urlencode "checksum=$CHECKSUM" \
    --data-urlencode "_=$TIMESTAMP" \
    -m 15 \
    "$RESUME_URL" 2>> "$LOG_FILE")

echo "Resume Status Output: $RESUME_OUT" | tee -a "$LOG_FILE"

# Extract dynamic session values returned by resume API
ACCESS_MODE=$(echo "$RESUME_OUT" | sed -n 's/.*"access_mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
MARKET_OPT_IN=$(echo "$RESUME_OUT" | sed -n 's/.*"market_opt_in"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
if [ -z "$MARKET_OPT_IN" ]; then
    MARKET_OPT_IN=$(echo "$RESUME_OUT" | sed -n 's/.*"market_opt_in"[[:space:]]*:[[:space:]]*\([a-z0-9]*\).*/\1/p')
fi
USERNAME=$(echo "$RESUME_OUT" | sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
AUTO_SIGN_IN_EXPIRED=$(echo "$RESUME_OUT" | sed -n 's/.*"auto_sign_in_expired"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
if [ -z "$AUTO_SIGN_IN_EXPIRED" ]; then
    AUTO_SIGN_IN_EXPIRED=$(echo "$RESUME_OUT" | sed -n 's/.*"auto_sign_in_expired"[[:space:]]*:[[:space:]]*\([a-z0-9]*\).*/\1/p')
fi

echo "Extracted session info:" | tee -a "$LOG_FILE"
echo "  ACCESS_MODE: $ACCESS_MODE" | tee -a "$LOG_FILE"
echo "  MARKET_OPT_IN: $MARKET_OPT_IN" | tee -a "$LOG_FILE"
echo "  USERNAME: $USERNAME" | tee -a "$LOG_FILE"
echo "  AUTO_SIGN_IN_EXPIRED: $AUTO_SIGN_IN_EXPIRED" | tee -a "$LOG_FILE"

echo "Stage 3: Submitting final login trigger..." | tee -a "$LOG_FILE"
FINAL_PARAMS="command=login&resume=true&lang=en"
FINAL_PARAMS="${FINAL_PARAMS}&sn=$(echo "$SN" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&ssid=$(echo "$SSID" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&ip=$(echo "$IP" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&client_mac=$(echo "$CLIENT_MAC" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&host_ip=$(echo "$HOST_IP" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&host_mac=$(echo "$HOST_MAC" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&time=$(echo "$TIME" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&cp_id=$(echo "$CP_ID" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&checksum=$(echo "$CHECKSUM" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&orig_url=$(echo "$ORIG_URL" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&browser=$(echo "$BROWSER" | sed 's/ /%20/g')"
FINAL_PARAMS="${FINAL_PARAMS}&_=${TIMESTAMP}"

if [ -n "$ACCESS_MODE" ]; then
    FINAL_PARAMS="${FINAL_PARAMS}&access_mode=$(echo "$ACCESS_MODE" | sed 's/ /%20/g')"
fi
if [ -n "$MARKET_OPT_IN" ]; then
    FINAL_PARAMS="${FINAL_PARAMS}&market_opt_in=$(echo "$MARKET_OPT_IN" | sed 's/ /%20/g')"
fi
if [ -n "$USERNAME" ]; then
    FINAL_PARAMS="${FINAL_PARAMS}&username=$(echo "$USERNAME" | sed 's/ /%20/g')"
fi
if [ -n "$AUTO_SIGN_IN_EXPIRED" ]; then
    FINAL_PARAMS="${FINAL_PARAMS}&auto_sign_in_expired=$(echo "$AUTO_SIGN_IN_EXPIRED" | sed 's/ /%20/g')"
fi

CURL_OUT=$(curl -k -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -m 15 \
    "https://${API_HOST}/cp/login?${FINAL_PARAMS}" 2>> "$LOG_FILE")

echo "Login Response: $CURL_OUT" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1
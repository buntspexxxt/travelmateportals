#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/wifi_login.log"
COOKIE_JAR="$(mktemp)"
HTML_OUT="$(mktemp)"
trap 'rm -f "${COOKIE_JAR}" "${HTML_OUT}"' EXIT

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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

echo "Fetching portal index to capture session cookies..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{url_effective}" -o "$HTML_OUT" -m 20 "http://neverssl.com" | tr -d '\015')

BASE_DOMAIN=$(echo "$EFFECTIVE_URL" | sed -n 's/\(https*:\/\/[^/]*\).*/\1/p')
echo "Base domain: $BASE_DOMAIN" | tee -a "$LOG_FILE"

echo "Extracting wbsToken..." | tee -a "$LOG_FILE"
TOKEN=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')

if [ -z "$TOKEN" ]; then
    echo "ERROR: Token extraction failed." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Initializing session..." | tee -a "$LOG_FILE"
curl -k -X POST -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -H "Content-Type: application/json" -d "{"token":"$TOKEN"}" -m 15 "$BASE_DOMAIN/wbs/api/v1/sessions" | tr -d '\015'

echo "Extracting scene ID..." | tee -a "$LOG_FILE"
SCENE_ID=$(sed -n 's/.*"id":"\([^"]*\)","module":"html-page-scene-wbs-new".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')

if [ ! -z "$SCENE_ID" ]; then
    echo "Applying scene configuration: $SCENE_ID" | tee -a "$LOG_FILE"
    curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 "$BASE_DOMAIN/wbs/api/v1/scenes/$SCENE_ID" | tr -d '\015'
fi

echo "Requesting final grant..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 "$BASE_DOMAIN/wbs/de/roaming/return/" | tr -d '\015'

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
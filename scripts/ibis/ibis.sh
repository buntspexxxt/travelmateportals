#!/bin/sh
# SCRIPT_VERSION="1.1.0"

trap 'rm -f "$COOKIE_FILE" "$HTML_OUT" "$POST_RESPONSE"' EXIT

echo "Waiting for IP, Gateway, and DNS..."
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
POST_RESPONSE=$(mktemp)
UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Step 1: Attempt to access neverssl.com..."
INITIAL_URL=$(curl -k -A "$UA_BROWSER" -o /dev/null -w "%{redirect_url}" -m 15 "http://neverssl.com")
echo "Redirected to: $INITIAL_URL"

if [ -z "$INITIAL_URL" ]; then
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ] && exit 0
    exit 1
fi

echo "Step 2: Establish session cookies..."
EFFECTIVE_URL=$(curl -k -L -A "$UA_BROWSER" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "$INITIAL_URL")

SCENE_PLAYER_URI=$(grep -o '"scenePlayerUri":"[^"]*"' "$HTML_OUT" | head -n 1 | sed 's/"scenePlayerUri":"\(.*\)"/\1/' | sed 's/\\\//\//g')
PORTAL_HOST=$(echo "$EFFECTIVE_URL" | awk -F/ '{print $1"//"$3}')

# The previous log shows the initial 'login' attempt returns a 200, suggesting a multi-step flow.
# Many Accor portals require an explicit 'accept' action or dynamic state transition.
LOGIN_URL="${PORTAL_HOST}${SCENE_PLAYER_URI}login"

echo "Step 3: Sending multi-part authentication payload..."
# We use the previously identified JSON structure and attempt to trigger the accept flow.
curl -k -i -A "$UA_BROWSER" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -H "Content-Type: application/json" \
    --data-binary '{"login":"","password":"","selected_tariff":"free","accept_terms":true,"remember_me":false}' \
    -m 15 "$LOGIN_URL" > "$POST_RESPONSE"

echo "Step 4: Verifying Internet connectivity..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet..."
    sleep 4
    i=$((i + 1))
done
exit 1
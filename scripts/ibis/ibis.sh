#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# 1. Wait for network readiness
echo "Waiting for IP, Gateway, and DNS..."
i=1
while [ \$i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!"
        sleep 2
        break
    fi
    sleep 1
    i=\$((i + 1))
done

COOKIE_FILE=\$(mktemp)
HTML_OUT=\$(mktemp)
trap 'rm -f "\$COOKIE_FILE" "\$HTML_OUT"' EXIT

UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Step 1: Triggering initial redirect..."
EFFECTIVE_URL=\$(curl -k -L -A "\$UA_BROWSER" -b "\$COOKIE_FILE" -c "\$COOKIE_FILE" -w "%\{url_effective\}" -o "\$HTML_OUT" -m 15 "http://neverssl.com")

echo "Step 2: Parsing scene config from HTML..."
SCENE_PLAYER_URI=\$(sed -n 's/.*"scenePlayerUri":"\([^"]*\)".*/\1/p' "\$HTML_OUT" | sed 's/\\\///g')
[ -z "\$SCENE_PLAYER_URI" ] && SCENE_PLAYER_URI="/sscp/iGKzCQzLrzwyM4q1/"
PORTAL_HOST=\$(echo "\$EFFECTIVE_URL" | awk -F/ '\{print \$1"//"\$3\}')
LOGIN_URL="\${PORTAL_HOST}\${SCENE_PLAYER_URI}login"

echo "Step 3: Authenticating..."
# Accor Conn4 portals typically use a specific JSON payload for the 'free' tariff.
# Note: Some hotels require accepting AGB (Terms) first, confirmed via the 'accept_terms' flag.
RESPONSE=\$(curl -k -i -A "\$UA_BROWSER" -b "\$COOKIE_FILE" -c "\$COOKIE_FILE" \
    -H "Content-Type: application/json" \
    --data-urlencode 'payload={"login":"","password":"","selected_tariff":"free","accept_terms":true}' \
    -X POST -m 15 "\$LOGIN_URL")

echo "Authentication Status: \$RESPONSE"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ \$i -le 10 ]; do
    CHECK_CODE=\$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "\$CHECK_CODE" = "204" ] || [ "\$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt \$i: Not connected yet (HTTP Check Code: \$CHECK_CODE). Waiting..."
    sleep 4
    i=\$((i + 1))
done
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds."
exit 1
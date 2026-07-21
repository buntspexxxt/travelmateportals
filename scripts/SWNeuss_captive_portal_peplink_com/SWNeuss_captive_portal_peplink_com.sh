#!/bin/sh
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Waiting for network..." | tee -a "$LOG_FILE"
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

echo "Fetching landing page..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
# Follow redirects to catch the true captive portal gate
EFFECTIVE_URL=$(curl -k -L -m 15 -A "$USER_AGENT" -w "%\{url_effective\}" -o "$HTML_OUT" "http://neverssl.com" | tr -d '\015')

echo "Analyzing page for redirection logic..." | tee -a "$LOG_FILE"
# The provided HTML uses JS to redirect to a subdomain of neverssl.com. We mimic the browser flow.
# We check for a meta refresh or document.location logic
REDIRECT_URL=$(grep -o "window.location.href = 'http://[^']*'" "$HTML_OUT" | sed "s/window.location.href = '\(.*\)'/\1/" | head -n 1)

if [ -n "$REDIRECT_URL" ]; then
    echo "JS-based redirect detected: $REDIRECT_URL" | tee -a "$LOG_FILE"
    curl -k -L -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$REDIRECT_URL" -o /dev/null
else
    # Fallback to checking for standard portal forms if no JS redirect found
    GRANT_URL=$(sed -n 's/.*action="\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1)
    if [ -n "$GRANT_URL" ]; then
        echo "Form detected, submitting empty credentials..." | tee -a "$LOG_FILE"
        curl -k -L -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$GRANT_URL" -d "accept=1" -o /dev/null
    fi
fi

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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
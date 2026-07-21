#!/bin/sh
# SCRIPT_VERSION="1.0.0"
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

echo "Fetching landing page to extract parameters..." | tee -a "$LOG_FILE"
HTML_OUT=$(mktemp)
EFFECTIVE_URL=$(curl -k -L -m 15 -A "$USER_AGENT" -w "%{url_effective}" -o "$HTML_OUT" "http://neverssl.com" | tr -d '\015')

echo "Analyzing page for grant URL..." | tee -a "$LOG_FILE"
# Extracting the grant URL from the HTML using sed as per requirements
GRANT_URL=$(sed -n 's/.*href="\([^"]*grant?continue_url=[^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | sed 's/&amp;/\&/g')

if [ -z "$GRANT_URL" ]; then
    echo "ERROR: Could not find grant URL in HTML." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Grant URL identified: $GRANT_URL" | tee -a "$LOG_FILE"

echo "Performing secondary authentication (Grant)..." | tee -a "$LOG_FILE"
# Performing a HEAD request to capture the 'Continue-Url' header as indicated by JS in HTML
RESPONSE_HEADERS=$(curl -k -v -I -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -H "X-Requested-With: XMLHttpRequest" "$GRANT_URL" 2>&1)
CONTINUE_URL=$(echo "$RESPONSE_HEADERS" | grep -i "Continue-Url" | sed 's/.*Continue-Url: //I' | tr -d '\015')

if [ -n "$CONTINUE_URL" ]; then
    echo "Redirecting to final continue URL: $CONTINUE_URL" | tee -a "$LOG_FILE"
    curl -k -L -m 15 -A "$USER_AGENT" -b "$COOKIE_FILE" "$CONTINUE_URL" -o /dev/null
else
    echo "Warning: Continue-Url header not found, proceeding with raw grant." | tee -a "$LOG_FILE"
fi

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
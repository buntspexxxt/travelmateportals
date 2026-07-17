#!/bin/sh
# SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Helper to decode HTML entities in a POSIX-compliant way
decode_html_entities() {
    local val="$1"
    echo "$val" | sed '
        s/&quot;/"/g;
        s/&amp;/\&/g;
        s/&#x27;/'\''/g;
        s/&#39;/'\''/g;
        s/&lt;/</g;
        s/&gt;/>/g;
        s/&#x3D;/=/g;
        s/&#61;/=/g;
    '
}

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

echo "Fetching initial Hotsplots portal page to find landing URL..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -m 15 -L -w "%{url_effective}" -o "$HTML_FILE" "http://neverssl.com")

# Strip any trailing carriage returns from the effective URL
EFFECTIVE_URL=$(echo "$EFFECTIVE_URL" | tr -d '\015')

echo "Effective landing URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

if [ -z "$EFFECTIVE_URL" ]; then
    echo "ERROR: Failed to retrieve effective landing URL." | tee -a "$LOG_FILE"
    exit 1
fi

# Extract query parameters from the effective URL
if echo "$EFFECTIVE_URL" | grep -q '?'; then
    QUERY_STRING=$(echo "$EFFECTIVE_URL" | cut -d'?' -f2-)
else
    QUERY_STRING=""
fi
echo "Extracted Query String: $QUERY_STRING" | tee -a "$LOG_FILE"

# Load downloaded HTML
if [ ! -f "$HTML_FILE" ]; then
    echo "ERROR: HTML file not found." | tee -a "$LOG_FILE"
    exit 1
fi
HTML=$(cat "$HTML_FILE")

# Helper to extract input values dynamically
get_input_value() {
    local name="$1"
    echo "$HTML" | sed -n "
    s/.*name="$name"[^>]*value="\([^"]*\)".*/\1/p;
    s/.*value="\([^"]*\)"[^>]*name="$name".*/\1/p
    " | head -n 1
}

HAVE_TERMS=$(get_input_value "haveTerms")
CHALLENGE=$(get_input_value "challenge")
UAMIP=$(get_input_value "uamip")
UAMPORT=$(get_input_value "uamport")
USERURL=$(get_input_value "userurl")
MYLOGIN=$(get_input_value "myLogin")
LL=$(get_input_value "ll")
NASID=$(get_input_value "nasid")
CUSTOM=$(get_input_value "custom")

# Decode HTML entities
HAVE_TERMS=$(decode_html_entities "$HAVE_TERMS")
CHALLENGE=$(decode_html_entities "$CHALLENGE")
UAMIP=$(decode_html_entities "$UAMIP")
UAMPORT=$(decode_html_entities "$UAMPORT")
USERURL=$(decode_html_entities "$USERURL")
MYLOGIN=$(decode_html_entities "$MYLOGIN")
LL=$(decode_html_entities "$LL")
NASID=$(decode_html_entities "$NASID")
CUSTOM=$(decode_html_entities "$CUSTOM")

echo "Extracted form fields:" | tee -a "$LOG_FILE"
echo "  haveTerms: $HAVE_TERMS" | tee -a "$LOG_FILE"
echo "  challenge: $CHALLENGE" | tee -a "$LOG_FILE"
echo "  uamip: $UAMIP" | tee -a "$LOG_FILE"
echo "  uamport: $UAMPORT" | tee -a "$LOG_FILE"
echo "  userurl: $USERURL" | tee -a "$LOG_FILE"
echo "  myLogin: $MYLOGIN" | tee -a "$LOG_FILE"
echo "  ll: $LL" | tee -a "$LOG_FILE"
echo "  nasid: $NASID" | tee -a "$LOG_FILE"
echo "  custom: $CUSTOM" | tee -a "$LOG_FILE"

# Prepare post destination
POST_URL="https://www.hotsplots.de/auth/login.php"
if [ -n "$QUERY_STRING" ]; then
    POST_URL="https://www.hotsplots.de/auth/login.php?${QUERY_STRING}"
fi

echo "Submitting terms acceptance form to $POST_URL..." | tee -a "$LOG_FILE"

RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 -L 
    --data-urlencode "haveTerms=${HAVE_TERMS:-1}" 
    --data-urlencode "termsOK=on" 
    --data-urlencode "challenge=${CHALLENGE}" 
    --data-urlencode "uamip=${UAMIP}" 
    --data-urlencode "uamport=${UAMPORT}" 
    --data-urlencode "userurl=${USERURL}" 
    --data-urlencode "myLogin=${MYLOGIN:-agb}" 
    --data-urlencode "ll=${LL:-de}" 
    --data-urlencode "nasid=${NASID}" 
    --data-urlencode "custom=${CUSTOM:-1}" 
    --data-urlencode "button=kostenlos einloggen" 
    "$POST_URL")

echo "Response from login submit (first 500 characters):" | tee -a "$LOG_FILE"
echo "$RESPONSE" | head -c 500 | tee -a "$LOG_FILE"

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
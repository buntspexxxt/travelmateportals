#!/bin/sh
# SCRIPT_VERSION="1.0.0"

# Exit on error
set -e

# Register EXIT trap to clean up files
trap 'rm -f "${COOKIE_FILE:-}" "${HTML_OUT:-}"' EXIT

COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

LOG_FILE="/tmp/portal_login.log"
echo "Starting T-Mobile HotSpot login script..." | tee -a "$LOG_FILE"

# 1. Wait for network readiness
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

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 2. Make initial request to trigger redirect and get cookies
echo "Requesting http://neverssl.com to trigger redirect..." | tee -a "$LOG_FILE"

# We use -w "%{url_effective}" to get the redirected URL
REDIRECT_URL=$(curl -k -A "$UA" -L -s -o /dev/null -w "%{url_effective}" --max-time 15 "http://neverssl.com")
echo "Effective Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

if [ -z "$REDIRECT_URL" ] || [ "$REDIRECT_URL" = "http://neverssl.com/" ] || [ "$REDIRECT_URL" = "http://neverssl.com" ]; then
    echo "Already connected or no redirect triggered." | tee -a "$LOG_FILE"
else
    # Fetch the portal landing page to establish cookies (JSESSIONID, DT_H, etc.)
    echo "Fetching landing page to establish session..." | tee -a "$LOG_FILE"
    curl -k -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -v --max-time 15 "$REDIRECT_URL" > "$HTML_OUT"
    
    # T-Mobile Hotspots typically have a free login/pass or online form.
    # Let's check for standard Telekom free-access endpoints or online-activation.
    # Often, the form submits to a location relative to /wlan/use_hotspot.do or similar.
    # Let's perform a POST to the standard Telekom free login endpoint if we can identify it,
    # or use the common query string parameters extracted from the REDIRECT_URL.

    # Extract query parameters from redirect URL
    QUERY_STRING=$(echo "$REDIRECT_URL" | grep -o '\?.*' | sed "s/\r//g" || true)
    echo "Query string parameters: $QUERY_STRING" | tee -a "$LOG_FILE"

    # For free hotspots (like airports, McDonald's, Railnet), the standard free-access submission URL is:
    # https://hotspot.t-mobile.net/wlan/use_hotspot.do
    # with parameters: strType=free or strType=pass & strPass=PASS_86400_0_EUR or voucherID
    
    # Let's try to activate the free voucher (PASS_86400_0_EUR is listed in pricing.vouchers as 1 Tag 0 EUR)
    echo "Submitting free pass login request..." | tee -a "$LOG_FILE"
    
    # Build base host from REDIRECT_URL
    BASE_HOST=$(echo "$REDIRECT_URL" | awk -F/ '{print $1"//"$3}')
    
    # Post data to use the free 24-hour voucher
    # In German Telekom hotspots, accepting the terms (AGB) and clicking "Online gehen" sends a POST or GET
    # to /wlan/use_hotspot.do with strType=free or similar.
    POST_URL="${BASE_HOST}/wlan/use_hotspot.do"
    
    echo "POSTing to: $POST_URL" | tee -a "$LOG_FILE"
    
    # We send both GET and POST trials because Telekom has changed endpoints over time.
    # Method 1: standard use_hotspot.do POST with strType=free
    RESPONSE=$(curl -k -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -d "strType=free&strAssented=true" -v -w "%{http_code}" --max-time 15 "$POST_URL" -o /dev/null || echo "000")
    echo "HTTP Response from POST 1: $RESPONSE" | tee -a "$LOG_FILE"
    
    # Method 2: MCD/Airport HappyHour often has its own endpoint or accept parameter
    # Let's try to post the free voucher ID explicitly if POST 1 didn't result in success
    VOUCHER_POST_URL="${BASE_HOST}/wlan/choose_tariff.do"
    echo "POSTing voucher selection to: $VOUCHER_POST_URL" | tee -a "$LOG_FILE"
    RESPONSE2=$(curl -k -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -d "voucherID=PASS_86400_0_EUR&strType=free&strAssented=true" -v -w "%{http_code}" --max-time 15 "$VOUCHER_POST_URL" -o /dev/null || echo "000")
    echo "HTTP Response from POST 2: $RESPONSE2" | tee -a "$LOG_FILE"
fi

# 3. Verify real Internet connectivity
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
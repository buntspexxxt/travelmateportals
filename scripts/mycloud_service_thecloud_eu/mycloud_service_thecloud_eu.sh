#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting Login Sequence..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching landing page to get initial session..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "https://service.thecloud.eu/service-platform/home")
echo "HTTP Response Code: $?" | tee -a "$LOG_FILE"

echo "Extracting the 'Get Online' navigation URL..." | tee -a "$LOG_FILE"
GET_ONLINE_URL=$(echo "$RESPONSE" | grep -o 'href="https://service.thecloud.eu/service-platform/url/[0-9]*"' | head -1 | cut -d'"' -f2)

if [ -z "$GET_ONLINE_URL" ]; then
    echo "Failed to find initial login URL. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Navigating to first step: $GET_ONLINE_URL" | tee -a "$LOG_FILE"
STEP1_RESPONSE=$(curl -v -L -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "$GET_ONLINE_URL")

echo "Analyzing page for final confirmation..." | tee -a "$LOG_FILE"
# The user hint suggests a two-page process. We now look for the final trigger.
FINAL_LINK=$(echo "$STEP1_RESPONSE" | grep -o 'href="https://service.thecloud.eu/service-platform/url/[0-9]*"' | head -1 | cut -d'"' -f2)

if [ -n "$FINAL_LINK" ]; then
    echo "Found final confirmation link: $FINAL_LINK. Navigating..." | tee -a "$LOG_FILE"
    curl -v -L -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "$FINAL_LINK"
else
    echo "No further links found, assuming already connected or redirected." | tee -a "$LOG_FILE"
fi

echo "Performing connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet reachable." | tee -a "$LOG_FILE" && exit 0 || exit 1
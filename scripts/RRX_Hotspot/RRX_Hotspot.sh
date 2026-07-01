#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting RRX_Hotspot automation check..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "The provided HTML is for 'NeverSSL', which is a cache-busting landing page typically used by routers to force browsers away from HTTPS to reveal a captive portal redirect." | tee -a "$LOG_FILE"
echo "This HTML contains no login form, no hidden fields, and no submit buttons. It simply triggers a Javascript redirect to a random subdomain of neverssl.com." | tee -a "$LOG_FILE"
echo "Since there is no actual login logic here and the page is just a redirector, this portal cannot be automated via simple curl form submission." | tee -a "$LOG_FILE"

echo "Performing connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Internet is already reachable." || echo "No internet access. Portal failed to redirect to a valid login page." | tee -a "$LOG_FILE"
exit 1
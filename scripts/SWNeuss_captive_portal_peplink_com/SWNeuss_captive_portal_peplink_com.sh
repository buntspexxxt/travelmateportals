#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting Captive Portal Login Script..." | tee -a "$LOG_FILE"

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

echo "Fetching landing page to extract session details..." | tee -a "$LOG_FILE"
# We target the captive portal domain directly. The JS shows it performs an AJAX check against /cp/session/resume
RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt "https://guest7.ic.peplink.com/cp/session/resume?client_mac=F2:C3:17:A1:A0:9F&sn=2939-508B-F086&ssid=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&time=1782720930&cp_id=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&checksum=4c92c10f3188fd41a416aef551388528bb5f24b3&_=1782720930")

echo "AJAX Session Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Performing final login request..." | tee -a "$LOG_FILE"
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?_=1782720930&command=login&lang=en&sn=2939-508B-F086&ssid=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&ip=10.200.9.44&client_mac=F2:C3:17:A1:A0:9F&host_ip=192.168.50.1&host_mac=A8:C0:EA:52:CA:60&cp_id=~CP_KEY_KoqKCOTKsie-rX87wdb1qA&checksum=4c92c10f3188fd41a416aef551388528bb5f24b3&orig_url=http://detectportal.firefox.com/success.txt"

LOGIN_RESULT=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt "$LOGIN_URL")
echo "Login Result Code: $?" | tee -a "$LOG_FILE"

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connected successfully!" && exit 0 || echo "Connection failed." && exit 1
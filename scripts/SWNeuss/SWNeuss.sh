#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting multi-stage Peplink portal login..." > "\$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "\$LOG_FILE"
i=1
while [ \$i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "\$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=\$((i + 1))
done

COOKIE_FILE=\$(mktemp)
HTML_FILE=\$(mktemp)
trap 'rm -f "\$COOKIE_FILE" "\$HTML_FILE"' EXIT

echo "Stage 1: Fetching initial redirect parameters..." | tee -a "\$LOG_FILE"
EFFECTIVE_URL=\$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -w "%\{url_effective\}" -o "\$HTML_FILE" -m 15 "http://neverssl.com" 2>> "\$LOG_FILE" | tr -d '\015')

get_param() {
    local name="\$1"
    local val="\$(echo "\$EFFECTIVE_URL" | sed -n "s/.*[?&]\${name}=\([^&]*\).*/\1/p")"
    if [ -z "\$val" ]; then
        val=\$(sed -n "s/.*\${name}:[[:space:]]*"\([^"]*\)".*/\1/p" "\$HTML_FILE" | head -n 1)
    fi
    echo "\$val"
}

CLIENT_MAC=\$(get_param "client_mac")
SN=\$(get_param "sn")
SSID=\$(get_param "ssid")
TIME=\$(get_param "time")
CP_ID=\$(get_param "cp_id")
CHECKSUM=\$(get_param "checksum")
IP=\$(get_param "ip")

if [ -z "\$CLIENT_MAC" ] || [ -z "\$SN" ] || [ -z "\$CHECKSUM" ]; then
    echo "ERROR: Failed to extract mandatory parameters." | tee -a "\$LOG_FILE"
    exit 1
fi

TIMESTAMP=\$(date +%s)000
API_HOST="guest7.ic.peplink.com"

echo "Stage 2: Attempting session resume..." | tee -a "\$LOG_FILE"
RESUME_OUT=\$(curl -k -v -A "Mozilla/5.0" -b "\$COOKIE_FILE" -c "\$COOKIE_FILE" -G \
    --data-urlencode "client_mac=\$CLIENT_MAC" --data-urlencode "sn=\$SN" \
    --data-urlencode "ssid=\$SSID" --data-urlencode "time=\$TIME" \
    --data-urlencode "cp_id=\$CP_ID" --data-urlencode "checksum=\$CHECKSUM" \
    --data-urlencode "_=\$TIMESTAMP" "https://\${API_HOST}/cp/session/resume" 2>> "\$LOG_FILE")

echo "Stage 3: Submitting login..." | tee -a "\$LOG_FILE"
curl -k -v -A "Mozilla/5.0" -b "\$COOKIE_FILE" -c "\$COOKIE_FILE" -d "command=login&resume=true&sn=\$SN&ssid=\$SSID&client_mac=\$CLIENT_MAC&cp_id=\$CP_ID&checksum=\$CHECKSUM&_= \$TIMESTAMP" "https://\${API_HOST}/cp/login" >> "\$LOG_FILE" 2>&1

echo "Verifying internet connectivity..." | tee -a "\$LOG_FILE"
i=1
while [ \$i -le 10 ]; do
    CHECK_CODE=\$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "\$CHECK_CODE" = "204" ] || [ "\$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "\$LOG_FILE"
        exit 0
    fi
    sleep 4
    i=\$((i + 1))
done
exit 1
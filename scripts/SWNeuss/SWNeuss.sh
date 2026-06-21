#!/bin/sh

CURL_OPTS="-k -s -L -c /tmp/c.txt -b /tmp/c.txt --max-time 15"
LANDING_URL=$(curl $CURL_OPTS -o /dev/null -w "%{\nurl_effective}" "http://detectportal.firefox.com/")

if [ -z "$LANDING_URL" ]; then
    exit 1
fi

QUERY_STRING=$(echo "$LANDING_URL" | grep -o '?.*' | cut -c 2-)

if [ -z "$QUERY_STRING" ]; then
    exit 1
fi

extract_param() {
    echo "$QUERY_STRING" | grep -oP "$1=\K[^&]*"
}

CLIENT_MAC=$(extract_param "client_mac")
SN=$(extract_param "sn")
SSID=$(extract_param "ssid")
TIME_PARAM=$(extract_param "time")
CP_ID=$(extract_param "cp_id")
CHECKSUM=$(extract_param "checksum")
IP=$(extract_param "ip")
HOTEL_IP=$(extract_param "host_ip")
HOTEL_MAC=$(extract_param "host_mac")
ORIG_URL=$(extract_param "orig_url")
BROWSER=$(extract_param "browser")

TIMESTAMP=$(date +%s%N | cut -b1-13)

LOGIN_BASE_URL="https://guest7.ic.peplink.com/cp/login"

BUILD_PARAMS=""
append_param() {
    if [ -n "$2" ]; then
        if [ -z "$BUILD_PARAMS" ]; then
            BUILD_PARAMS="$(printf "%s=%s" "$1" "$2")"
        else
            BUILD_PARAMS="${BUILD_PARAMS}&$(printf "%s=%s" "$1" "$2")"
        fi
    fi
}

append_param "_" "$TIMESTAMP"
append_param "access_mode" ""
append_param "market_opt_in" ""
append_param "username" ""
append_param "auto_sign_in_expired" ""
append_param "resume" "true"
append_param "command" "login"
append_param "lang" "en"
append_param "sn" "$SN"
append_param "ssid" "$SSID"
append_param "ip" "$IP"
append_param "client_mac" "$CLIENT_MAC"
append_param "host_ip" "$HOTEL_IP"
append_param "host_mac" "$HOTEL_MAC"
append_param "name" ""
append_param "time" "$TIME_PARAM"
append_param "cp_id" "$CP_ID"
append_param "checksum" "$CHECKSUM"
append_param "orig_url" "$ORIG_URL"
append_param "browser" "$BROWSER"

curl $CURL_OPTS "${LOGIN_BASE_URL}?${BUILD_PARAMS}" > /dev/null

check_quota() {
    local QUOTA_URL="https://guest7.ic.peplink.com/cp/"
    local QUOTA_PARAMS=""
    local ts=$(date +%s%N | cut -b1-13)

    local append_quota_param() {
        if [ -n "$2" ]; then
            if [ -z "$QUOTA_PARAMS" ]; then
                QUOTA_PARAMS="$(printf "%s=%s" "$1" "$2")"
            else
                QUOTA_PARAMS="${QUOTA_PARAMS}&$(printf "%s=%s" "$1" "$2")"
            fi
        fi
    }

    append_quota_param "_" "$ts"
    append_quota_param "access_mode" ""
    append_quota_param "market_opt_in" ""
    append_quota_param "username" ""
    append_quota_param "resume" "true"
    append_quota_param "command" "quota_exceed"
    append_quota_param "lang" "en"
    append_quota_param "sn" "$SN"
    append_quota_param "ssid" "$SSID"
    append_quota_param "ip" "$IP"
    append_quota_param "client_mac" "$CLIENT_MAC"
    append_quota_param "host_ip" "$HOTEL_IP"
    append_quota_param "host_mac" "$HOTEL_MAC"
    append_quota_param "name" ""
    append_quota_param "time" "$TIME_PARAM"
    append_quota_param "cp_id" "$CP_ID"
    append_quota_param "checksum" "$CHECKSUM"
    append_quota_param "orig_url" "$ORIG_URL"
    append_quota_param "browser" "$BROWSER"

    curl $CURL_OPTS "${QUOTA_URL}?${QUOTA_PARAMS}"
}

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
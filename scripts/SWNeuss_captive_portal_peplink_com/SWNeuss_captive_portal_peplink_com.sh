#!/bin/sh

CURL_COOKIE_JAR=$(mktemp)

INITIAL_URL="http://detectportal.firefox.com/"
LANDING_URL=$(curl -sS -L -o /dev/null -w "%{\nurl_effective}" -c "$CURL_COOKIE_JAR" "$INITIAL_URL")

if [ -z "$LANDING_URL" ]; then
    rm -f "$CURL_COOKIE_JAR"
    exit 1
fi

QUERY_STRING=$(echo "$LANDING_URL" | grep -o '?.*' | cut -c 2-)

if [ -z "$QUERY_STRING" ]; then
    rm -f "$CURL_COOKIE_JAR"
    exit 1
fi

CLIENT_MAC=$(echo "$QUERY_STRING" | grep -oP 'client_mac=\K[^&]*')
SN=$(echo "$QUERY_STRING" | grep -oP 'sn=\K[^&]*')
SSID=$(echo "$QUERY_STRING" | grep -oP 'ssid=\K[^&]*')
TIME=$(echo "$QUERY_STRING" | grep -oP 'time=\K[^&]*')
CP_ID=$(echo "$QUERY_STRING" | grep -oP 'cp_id=\K[^&]*')
CHECKSUM=$(echo "$QUERY_STRING" | grep -oP 'checksum=\K[^&]*')

RESUME_SESSION_BASE_URL="https://guest7.ic.peplink.com/cp/session/resume"
RESUME_SESSION_PARAMS="client_mac=${CLIENT_MAC}&sn=${SN}&ssid=${SSID}&time=${TIME}&cp_id=${CP_ID}&checksum=${CHECKSUM}&_=$(date +%s%N | cut -b1-13)"
RESUME_SESSION_URL="${RESUME_SESSION_BASE_URL}?${RESUME_SESSION_PARAMS}"

curl -sS -L -b "$CURL_COOKIE_JAR" -c "$CURL_COOKIE_JAR" -o /dev/null "$RESUME_SESSION_URL"

rm -f "$CURL_COOKIE_JAR"

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
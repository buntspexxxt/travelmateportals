#!/bin/sh

COOKIE_FILE=$(mktemp)

LANDING_URL=$(curl -s -L -D /dev/stderr -o /dev/null -c "$COOKIE_FILE" -w "%{\nurl_effective}" "http://detectportal.firefox.com/")

BASE_URL=$(echo "$LANDING_URL" | grep -oE 'https?://[^/]+')

GET_ONLINE_URL="${BASE_URL}/service-platform/url/20347"

curl -s -L -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$GET_ONLINE_URL" > /dev/null

rm -f "$COOKIE_FILE"

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
#!/bin/sh

COOKIE_FILE=$(mktemp)
PORTAL_CHECK_URL="http://detectportal.firefox.com/"

LANDING_URL=$(curl -L -c "$COOKIE_FILE" -s -o /dev/null -w "%{url_effective}" "$PORTAL_CHECK_URL")
QUERY_STRING=$(echo "$LANDING_URL" | grep -o '?.*' | cut -c 2-)

# Download HTML to extract hidden fields
HTML_CONTENT=$(curl -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -s "$LANDING_URL")
FX_username=$(echo "$HTML_CONTENT" | grep -ioE 'name="FX_username"\s+value="[^"]*"' | sed -E 's/.*value="([^"]+)".*/\1/' | head -n 1)
FX_loginTemplate=$(echo "$HTML_CONTENT" | grep -ioE 'name="FX_loginTemplate"\s+value="[^"]*"' | sed -E 's/.*value="([^"]+)".*/\1/' | head -n 1)
FX_hotspotDeviceId=$(echo "$HTML_CONTENT" | grep -ioE 'name="FX_hotspotDeviceId"\s+value="[^"]*"' | sed -E 's/.*value="([^"]+)".*/\1/' | head -n 1)

# If grep fails, fall back to empty to prevent script crash
FX_username=${FX_username:-""}
FX_loginTemplate=${FX_loginTemplate:-""}
FX_hotspotDeviceId=${FX_hotspotDeviceId:-""}

curl -L -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST \
  -d "$QUERY_STRING" \
  -d "cbQpC=1" \
  --data-urlencode "FX_username=$FX_username" \
  -d "FX_password=easy" \
  --data-urlencode "FX_loginTemplate=$FX_loginTemplate" \
  --data-urlencode "FX_loginType=Easy Login" \
  -d "FX_remoteAddr=" \
  --data-urlencode "FX_hotspotDeviceId=$FX_hotspotDeviceId" \
  -d "FX_lang=" \
  -s -o /dev/null "$LANDING_URL"

rm "$COOKIE_FILE"

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1

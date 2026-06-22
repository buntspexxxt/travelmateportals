#!/bin/sh

COOKIE_JAR=$(mktemp)
HTML_CONTENT=$(mktemp)

INITIAL_PORTAL_URL="$1"

EFFECTIVE_URL=$(curl -L -k -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o "$HTML_CONTENT" -w '%{url_effective}' "$INITIAL_PORTAL_URL" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$EFFECTIVE_URL" ] || [ ! -s "$HTML_CONTENT" ]; then
    rm "$COOKIE_JAR" "$HTML_CONTENT"
    exit 1
fi

GET_ONLINE_FULL_URL_RAW=$(grep -oP "<a[^>]*href='(?:http|https)://[^']*/service-platform/url/20347'" "$HTML_CONTENT" | head -n 1 | sed -n "s/.*href='\([^']*\)'.*/\1/p")

if [ -z "$GET_ONLINE_FULL_URL_RAW" ]; then
    rm "$COOKIE_JAR" "$HTML_CONTENT"
    exit 1
fi

LOGIN_PROTOCOL=$(echo "$EFFECTIVE_URL" | grep -oP 'https?://' | head -n 1)
LOGIN_HOST=$(echo "$GET_ONLINE_FULL_URL_RAW" | grep -oP '(?<=https?://)[^/]+' | head -n 1)
LOGIN_PATH=$(echo "$GET_ONLINE_FULL_URL_RAW" | grep -oP '(?<=https?://[^/]+).*' | head -n 1)

LOGIN_URL="${LOGIN_PROTOCOL}${LOGIN_HOST}${LOGIN_PATH}"

curl -L -k -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o /dev/null "$LOGIN_URL"

rm "$COOKIE_JAR" "$HTML_CONTENT"

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
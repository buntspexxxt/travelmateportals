#!/bin/sh
COOKIE_JAR=$(mktemp)
LANDING_URL="http://neverssl.com/"

curl -s -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$LANDING_URL" > /dev/null

rm -f "$COOKIE_JAR"

ping -c 3 8.8.8.8 >/dev/null
if [ $? -eq 0 ]; then
    exit 0
else
    exit 1
fi
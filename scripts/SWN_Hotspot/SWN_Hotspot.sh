#!/bin/sh

COOKIE_JAR=$(mktemp)

INITIAL_PROBE_URL="http://detectportal.firefox.com/"
LANDING_URL=$(curl -s -L -c "$COOKIE_JAR" -o /dev/null -w "%{url_effective}" "$INITIAL_PROBE_URL")

BASE_URL=$(echo "$LANDING_URL" | grep -oP 'https://[^/]+')
LOGIN_PATH=$(echo "$LANDING_URL" | grep -oP '/auth/login.php')
LOGIN_URL="${BASE_URL}${LOGIN_PATH}"

UAMIP=$(echo "$LANDING_URL" | grep -oP 'uamip=\K[^&]*')
UAMPORT=$(echo "$LANDING_URL" | grep -oP 'uamport=\K[^&]*')
CHALLENGE=$(echo "$LANDING_URL" | grep -oP 'challenge=\K[^&]*')
NASID=$(echo "$LANDING_URL" | grep -oP 'nasid=\K[^&]*')
USERURL=$(echo "$LANDING_URL" | grep -oP 'userurl=\K[^&]*')

POST_DATA="haveTerms=1&termsOK=1&challenge=${CHALLENGE}&uamip=${UAMIP}&uamport=${UAMPORT}&userurl=${USERURL}&myLogin=agb&ll=de&nasid=${NASID}&custom=0&button=kostenlos+einloggen"

curl -s -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X POST -d "$POST_DATA" "$LOGIN_URL" -o /dev/null

rm -f "$COOKIE_JAR"

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
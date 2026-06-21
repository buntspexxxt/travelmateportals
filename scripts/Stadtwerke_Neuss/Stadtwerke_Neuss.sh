#!/bin/sh

LANDING_URL=$1
COOKIE_JAR=$(mktemp)

EFFECTIVE_URL=$(curl -sS -L -c "$COOKIE_JAR" -o /dev/null -w "%{\nurl_effective}" "$LANDING_URL")

UAMIP=$(echo "$EFFECTIVE_URL" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$EFFECTIVE_URL" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
CHALLENGE=$(echo "$EFFECTIVE_URL" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
NASID=$(echo "$EFFECTIVE_URL" | sed -n 's/.*nasid=\([^&]*\).*/\1/p')
USERURL_ENCODED=$(echo "$EFFECTIVE_URL" | sed -n 's/.*userurl=\([^&]*\).*/\1/p')

POST_URL="https://www.hotsplots.de/auth/login.php"

POST_DATA="haveTerms=1&termsOK=on&button=kostenlos%20einloggen&challenge=${CHALLENGE}&uamip=${UAMIP}&uamport=${UAMPORT}&userurl=${USERURL_ENCODED}&myLogin=agb&ll=de&nasid=${NASID}&custom=1"

curl -sS -L -b "$COOKIE_JAR" -d "$POST_DATA" "$POST_URL" -o /dev/null

rm "$COOKIE_JAR"

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
#!/bin/sh

COOKIE_FILE=$(mktemp)
PORTAL_CHECK_URL="http://detectportal.firefox.com/"

LANDING_URL=$(curl -L -c "$COOKIE_FILE" -s -o /dev/null -w "%{url_effective}" "$PORTAL_CHECK_URL")
QUERY_STRING=$(echo "$LANDING_URL" | grep -o '?.*' | cut -c 2-)

POST_DATA="${QUERY_STRING}&cbQpC=1&FX_username=VMPZcklP4gurLgw5zPEcHjfUQa4%3D&FX_password=easy&FX_loginTemplate=5da450a5ba69df00072ddd76&FX_loginType=Easy+Login&FX_remoteAddr=&FX_hotspotDeviceId=5e6bfafc7799f2000a99accf&FX_lang="

curl -L -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST -d "$POST_DATA" -s -o /dev/null "$LANDING_URL"

rm "$COOKIE_FILE"

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1

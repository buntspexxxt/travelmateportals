#!/bin/sh

COOKIE_FILE=$(mktemp)
PORTAL_CHECK_URL="http://detectportal.firefox.com/"

LANDING_URL=$(curl -L -c "$COOKIE_FILE" -s -o /dev/null -w "%{\nurl_effective}" "$PORTAL_CHECK_URL")

POST_DATA="cbQpC=1&nasid=00-0d-b9-4f-e3-55&mac=26-D8-32-CB-EC-DD&challenge=489703607482e8f989e5b2c287990d39&uamip=172.17.248.1&uamport=3990&called=00-0D-B9-4F-E3-55&userurl=http%3A%2F%2Fdetectportal.firefox.com%2F&sessionid=6a36b1430000000b&FX_username=VMPZcklP4gurLgw5zPEcHjfUQa4%3D&FX_password=easy&FX_loginTemplate=5da450a5ba69df00072ddd76&FX_loginType=Easy+Login&FX_remoteAddr=&FX_hotspotDeviceId=5e6bfafc7799f2000a99accf&FX_lang="

curl -L -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST -d "$POST_DATA" -s -o /dev/null "$LANDING_URL"

rm "$COOKIE_FILE"

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
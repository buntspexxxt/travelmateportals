#!/bin/sh

COOKIE_FILE=$(mktemp)

HTML_AND_URL=$(curl -L -s -c "${COOKIE_FILE}" -b "${COOKIE_FILE}" -o /dev/stdout -w "%{\nurl_effective}" "http://detectportal.firefox.com/")

LANDING_URL=$(echo "$HTML_AND_URL" | tail -n 1)
HTML_CONTENT=$(echo "$HTML_AND_URL" | head -n -1)

BASE_DOMAIN=$(echo "$LANDING_URL" | awk -F'/' '{print $3}' | cut -d'?' -f1)

POST_ACTION_URL=$(echo "$HTML_CONTENT" | grep -oP '<form name="FX_loginform_0"[^>]*action="\K[^"]*' | head -n 1 | sed 's/&amp;/&/g')

if [ -z "$POST_ACTION_URL" ]; then
    exit 1
fi

POST_DATA=$(echo "$HTML_CONTENT" | awk '/<form name="FX_loginform_0"/,/</form>/ {
    if ($0 ~ /<input type="hidden"/) {
        match($0, /name="([^"]*)"/); name = substr($0, RSTART + 6, RLENGTH - 7);
        match($0, /value="([^"]*)"/); value = substr($0, RSTART + 7, RLENGTH - 8);
        gsub(/&#x3D;/, "=", value); 
        if (name != "" && value != "") {
            if (post_data != "") { post_data = post_data "&" }
            post_data = post_data name "=" value
        }
    }
} END { print post_data }')


if [ -z "$POST_DATA" ]; then
    exit 1
fi

curl -s -L -c "${COOKIE_FILE}" -b "${COOKIE_FILE}" -X POST -d "${POST_DATA}" "${POST_ACTION_URL}" > /dev/null

rm "${COOKIE_FILE}"

ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
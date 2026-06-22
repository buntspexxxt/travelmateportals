#!/bin/sh

COOKIE_FILE=$(mktemp)

# Step 1: Follow redirects from the initial URL to reach the portal home page
# and save cookies. Also capture the effective URL and HTML content.
INITIAL_URL="http://detectportal.firefox.com/"

# Curl will follow redirects and handle HSTS for service.thecloud.eu automatically.
# The output format is: HTML_BODY\nEFFECTIVE_URL
HOME_PAGE_INFO=$(curl -s -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -w "%\n{url_effective}" "$INITIAL_URL")

HOME_PAGE_URL=$(echo "$HOME_PAGE_INFO" | tail -n 1)
HOME_PAGE_HTML=$(echo "$HOME_PAGE_INFO" | head -n -1)

# Check if the home page URL was successfully obtained
if [ -z "$HOME_PAGE_URL" ]; then
  echo "Failed to get portal home page URL." >&2
  rm "$COOKIE_FILE"
  exit 1
fi

# Extract the 'Get Online' link from the HTML. 
# It looks like <a class="actionable" href='http://service.thecloud.eu/service-platform/url/20347'>...<span>Get Online</span>...</a>
GET_ONLINE_LINK=$(echo "$HOME_PAGE_HTML" | grep -oP "<a[^>]*href='([^']*)'.*?>.*?<span>Get Online</span>.*?</a>" | head -n 1 | grep -oP "href='([^']*)'" | cut -d"'" -f2)

# Ensure the extracted link is absolute and uses HTTPS if the final portal page was HTTPS (due to HSTS)
# This specific portal already used HSTS to redirect to HTTPS, so we'll enforce it for the login link too.
if echo "$GET_ONLINE_LINK" | grep -q "^http://"; then
  GET_ONLINE_LINK=$(echo "$GET_ONLINE_LINK" | sed 's/^http:/https:/')
fi

if [ -z "$GET_ONLINE_LINK" ]; then
  echo "Failed to find 'Get Online' link on the portal page." >&2
  rm "$COOKIE_FILE"
  exit 1
fi

# Step 2: Access the 'Get Online' link to activate the internet connection
curl -s -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$GET_ONLINE_LINK" >/dev/null

# Step 3: Clean up the cookie file and perform a connectivity check
rm "$COOKIE_FILE"
ping -c 3 8.8.8.8 >/dev/null && exit 0 || exit 1
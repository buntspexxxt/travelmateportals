#!/bin/sh
# Auto-generated Travelmate Script for LidlPlusWlan
TARGET_URL="http://detectportal.firefox.com/success.txt"
PORTAL_HTML=$(curl -s -L "$TARGET_URL")

echo "Attempting to parse and submit login form..."
POST_DATA=""
ACTION_URL=""

# Extract form action if relative or absolute
FORM_ACTION=$(echo "$PORTAL_HTML" | grep -iEo 'action="([^"]+)"' | head -n1 | sed -E 's/action="([^"]+)"/\1/i')
if [ -n "$FORM_ACTION" ]; then
    if echo "$FORM_ACTION" | grep -q "^http"; then
        ACTION_URL="$FORM_ACTION"
    elif echo "$FORM_ACTION" | grep -q "^/"; then
        # Needs base URL extraction, simplify for now
        ACTION_URL="http://172.17.248.1:3990${FORM_ACTION}"
    else
        ACTION_URL="http://172.17.248.1:3990/${FORM_ACTION}"
    fi
fi

# Extract hidden inputs
POST_DATA=$(echo "$PORTAL_HTML" | grep -iE 'input[^>]+type=["'\'']?(hidden|submit|checkbox)["'\'']?' | \
    sed -E 's/.*name=["'\'']([^"'\'']+)["'\''].*value=["'\'']([^"'\'']*)["'\''].*/\1=\2/' | \
    grep -v '<input' | paste -sd "&" -)

if [ -z "$POST_DATA" ]; then
    # Fallback to hardcoded inputs if parsing fails
    POST_DATA=""
fi

echo "Submitting to $ACTION_URL with data: $POST_DATA"
curl -s -L -G --data-urlencode "$POST_DATA" "$ACTION_URL" > /dev/null
exit 0

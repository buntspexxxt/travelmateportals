#!/bin/sh
# Captive Portal Auto-Login für WiFi4EU (The Cloud Networks Germany GmbH)
# Automatisch generiert aus gesammeltem Captive Portal HTML

CP_URL=${CAPTIVE_PORTAL_URL:-"http://www.msftconnecttest.com/connecttest.txt"}

# Hole die Captive Portal Seite
HTML_CONTENT=$(curl -s -L --connect-timeout 5 "$CP_URL")

# Die Basis-URL des Portals extrahieren (z.B. http://10.4.0.31)
PORTAL_BASE=$(echo "$CP_URL" | grep -o '^http[s]*://[^/]*')
if [ -z "$PORTAL_BASE" ]; then
    PORTAL_BASE="http://10.4.0.31"
fi

# Extrahiere die URL für den "Get Online" Button (The Cloud nutzt oft /service-platform/url/XXXX)
ACTION_PATH=$(echo "$HTML_CONTENT" | grep -oE "href='/service-platform/url/[0-9]+'" | head -n 1 | cut -d"'" -f2)

if [ -n "$ACTION_PATH" ]; then
    LOGIN_URL="${PORTAL_BASE}${ACTION_PATH}"
    curl -s -L -A "Mozilla/5.0" --connect-timeout 10 "$LOGIN_URL" > /dev/null
    exit 0
else
    # Fallback, falls RegExp fehlschlägt
    curl -s -L -A "Mozilla/5.0" --connect-timeout 10 "${PORTAL_BASE}/service-platform/url/20347" > /dev/null
    exit 0
fi

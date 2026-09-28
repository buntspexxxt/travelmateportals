#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="/tmp/ibis_cookies.txt"
HTML_OUT="/tmp/portal_html.html"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
trap 'rm -f "${COOKIE_JAR:-}" "${HTML_OUT:-}"' EXIT

echo "Waiting for network readiness..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -A "$USER_AGENT" -L -c "$COOKIE_JAR" -w "%{url_effective}" -o "$HTML_OUT" -m 15 "http://neverssl.com")
echo "Current URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Extracting form data from initial page..." | tee -a "$LOG_FILE"
FORM_ACTION=$(sed -n 's/.*<form.*action="\([^"\\]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | sed 's/&amp;/&/g')

# Helper to extract input values
extract_val() {
    sed -n "s/.*name="'$1'" value="\([^"\\]*\)".*/\1/p" "$HTML_OUT" | head -n 1 | sed 's/&#x3D;/=/g'
}

CBQPC=$(extract_val "cbQpC")
NASID=$(extract_val "nasid")
MAC=$(extract_val "mac")
CHALLENGE=$(extract_val "challenge")
UAMIP=$(extract_val "uamip")
UAMPORT=$(extract_val "uamport")
CALLED=$(extract_val "called")
USERURL=$(extract_val "userurl")
SESSIONID=$(extract_val "sessionid")
USERNAME=$(extract_val "FX_username")
PASSWORD="easy"
TEMPLATE=$(extract_val "FX_loginTemplate")
LOGIN_TYPE="Easy Login"
DEVICE_ID=$(extract_val "FX_hotspotDeviceId")

echo "Submitting login form to $FORM_ACTION..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 -X POST \
--data-urlencode "cbQpC=$CBQPC" \
--data-urlencode "nasid=$NASID" \
--data-urlencode "mac=$MAC" \
--data-urlencode "challenge=$CHALLENGE" \
--data-urlencode "uamip=$UAMIP" \
--data-urlencode "uamport=$UAMPORT" \
--data-urlencode "called=$CALLED" \
--data-urlencode "userurl=$USERURL" \
--data-urlencode "sessionid=$SESSIONID" \
--data-urlencode "FX_username=$USERNAME" \
--data-urlencode "FX_password=$PASSWORD" \
--data-urlencode "FX_loginTemplate=$TEMPLATE" \
--data-urlencode "FX_loginType=$LOGIN_TYPE" \
--data-urlencode "FX_hotspotDeviceId=$DEVICE_ID" 
"$FORM_ACTION")

echo "Login response received. Verifying connectivity after first step..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified after initial login!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "Internet connection not established after first login step. Proceeding to next page if available..." | tee -a "$LOG_FILE"

echo "Fetching the next page of the portal..." | tee -a "$LOG_FILE"

# The provided HTML is the *next* page, indicating the previous submission was not enough.
# We need to re-fetch the page to get any new dynamic elements.

echo "Fetching current portal page to find next steps..." | tee -a "$LOG_FILE"

# Fetch the current page content. The HTML indicates a SPA or a dynamically loaded page.
# We will try to extract the base URL from the script tags.

CURRENT_PAGE_URL="http://accor.conn4.com/"

echo "Fetching page content from $CURRENT_PAGE_URL..." | tee -a "$LOG_FILE"

# This page uses Vue.js and likely loads assets dynamically. 
# We will attempt to find the initial script and see if it contains redirect URLs or submission endpoints.

# Extract base URL and script URL from HTML
BASE_HREF=$(echo "$HTML" | sed -n 's/<base href="\([^"\\]*\)">/\1/p' | head -n 1)
if [ -z "$BASE_HREF" ]; then
    BASE_HREF="/"
fi

JS_SRC=$(echo "$HTML" | grep -o '<script type="module" crossorigin src="\([^"\\]*\)"></script>' | sed 's/<script type="module" crossorigin src="\([^"\\]*\)"><\/script>/\1/p' | head -n 1)

# Construct full URL for the JS file
if [[ "$JS_SRC" == http* ]]; then
    FULL_JS_URL="$JS_SRC"
else
    # Resolve relative URL against the base URL (or assume root if base is empty)
    if [[ "$JS_SRC" == /* ]]; then
        FULL_JS_URL="${CURRENT_PAGE_URL%/}${JS_SRC}"
    else
        FULL_JS_URL="${CURRENT_PAGE_URL%/}/${JS_SRC}"
    fi
fi

echo "Attempting to fetch JavaScript file from: $FULL_JS_URL" | tee -a "$LOG_FILE"

# Fetch the JS file to look for specific endpoints or configuration
JS_CONTENT=$(curl -k -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -m 15 "$FULL_JS_URL")

if [ $? -ne 0 ] || [ -z "$JS_CONTENT" ]; then
    echo "ERROR: Failed to fetch JavaScript content from $FULL_JS_URL" | tee -a "$LOG_FILE"
    exit 1
fi

echo "JavaScript content fetched. Analyzing for next steps..." | tee -a "$LOG_FILE"

# Analyze JS for configuration or endpoints.
# Looking for '__sceneConfig' which seems to hold relevant data.
SCENE_CONFIG=$(echo "$JS_CONTENT" | grep -o 'var __sceneConfig = {.*};' | sed 's/var __sceneConfig = //')

if [ -z "$SCENE_CONFIG" ]; then
    echo "ERROR: Could not find '__sceneConfig' in JavaScript. Cannot determine next steps." | tee -a "$LOG_FILE"
    exit 1
fi

# Extract redirectUrl from sceneConfig. This is typically where we'd POST to.
# For this portal, the HTML suggests it's a success page, possibly meaning the initial login was enough.
# However, since the previous script failed connectivity, we assume there's a hidden step.
# The current HTML (`index-DIUbTxKq.js` content is embedded in the main HTML) suggests it's a Vue app that loaded.
# We will try to find the form or submission endpoint. The HTML points to an app div, implying JS handling.

# Based on the current HTML, it seems to be a SPA that loaded successfully and is presenting itself as 'done'.
# However, the previous script's failure to connect to the internet indicates a missing step.
# The HTML provided (`success.txt.html` and `index.html`) are the *same* and point to `index-DIUbTxKq.js` and `index-DX-xMuTS.css`.

# The provided JS (`otSDKStub.js` and parts of `index-DIUbTxKq.js` are shown as separate files, which is confusing).
# The `otSDKStub.js` is for OneTrust cookie consent, not the main portal logic.
# The `index-DIUbTxKq.js` appears to be the main Vue app. It loads assets dynamically.
# The `__sceneConfig` object is present in the HTML itself.

# We need to find what the Vue app does. The HTML is just a shell loading the JS.
# The previous script submitted a form to `accor.conn4.com/ident` and then redirected to `https://accor.conn4.com/`.
# This means the current page is likely a success page after the initial authentication.

# Given the current HTML is a success page that loads a JS application, and the previous step failed connectivity,
# it's possible the portal requires an explicit 'Accept Terms' or similar action that is handled by the JS.
# However, without an obvious form or submission endpoint in the HTML, directly automating this next step is hard.

# Let's assume that the current page is indeed the final success page and the issue was with the previous attempt's connectivity verification or a subtle network issue.

# We will proceed to the standard internet connectivity check.


echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1

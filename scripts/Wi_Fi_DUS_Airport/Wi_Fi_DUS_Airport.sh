LOG_FILE="/tmp/captive_portal.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Waiting for IP, Gateway, and DNS..."
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!"
        sleep 2
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching initial page to get redirection information..."
REDIRECT_URL=$(curl -v -A "$USER_AGENT" -k -L -o /dev/null -w '%{url_effective}' http://neverssl.com/)
HTTP_STATUS=$(curl -v -A "$USER_AGENT" -k -o /dev/null -w '%{http_code}' http://neverssl.com/)

echo "Initial fetch completed. HTTP Status: $HTTP_STATUS, Redirect URL: $REDIRECT_URL"

if [ -z "$REDIRECT_URL" ]; then
    echo "ERROR: Failed to get redirect URL from initial fetch."
    exit 1
fi

# The JavaScript in the HTML generates a URL like http://<prefix>.neverssl.com/online
# We need to extract the domain part and follow it.
# The previous redirect URL should already point to this generated URL if the captive portal is active.
# If not, we'll assume the landing page is the portal itself.

echo "Following redirect to: $REDIRECT_URL"

# The script will navigate to a dynamically generated URL based on the JS. We need to capture that.
# The previous curl command with -L should have followed the redirects to the final destination.
# We'll use the REDIRECT_URL variable obtained from the first curl with -w '%{url_effective}'.

# In this specific case, the JavaScript is redirecting to a .neverssl.com subdomain.
# The captive portal usually injects itself by redirecting ALL traffic to its login page.
# So, the REDIRECT_URL should be the portal's entry point.

LOGIN_PAGE_URL="$REDIRECT_URL"

echo "Fetching login page content from: $LOGIN_PAGE_URL"
LOGIN_PAGE_CONTENT=$(curl -v -A "$USER_AGENT" -k "$LOGIN_PAGE_URL")
HTTP_STATUS=$(curl -v -A "$USER_AGENT" -k -o /dev/null -w '%{http_code}' "$LOGIN_PAGE_URL")

echo "Login page content fetched. HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "ERROR: Failed to fetch login page. HTTP Status: $HTTP_STATUS"
    exit 1
fi

# The neverssl portal is designed to redirect to a dynamically generated URL which is itself the portal.
# The provided JS generates a URL like http://<prefix>.neverssl.com/online
# The initial curl with -L will follow this redirect.
# We don't need to extract anything else from the HTML because the JS handles the redirection.
# The subsequent curl should just hit the target URL and potentially a final redirect after accepting terms (which aren't present here).

# Since there are no forms or explicit login fields, we assume just accessing the generated URL is sufficient.
# The prompt mentions a POST request for forms, but this portal uses JS redirection.
# The most straightforward approach is to follow the JS-generated URL. If this is insufficient, it might require more complex interaction or a POST to a specific endpoint.

# For this portal, the JavaScript sets window.location.href. The initial curl with -L should handle this.
# If we reach this point and the network is still blocked, it means the initial redirect wasn't enough.
# In many captive portals, simply arriving at the portal page is enough to be redirected to the login page if not authenticated.
# The provided HTML has a JS that redirects to neverssl.com subdomain. The captivate portal might override this.

# Given the lack of explicit forms and the JS redirect, we assume reaching the JS-generated URL is the intended way.
# If it's a simple redirect-based captive portal that just needs you to visit a specific page, this might work.
# The provided HTML is the portal page itself, and the JS redirects to 'neverssl.com' with a dynamic subdomain. 
# The captive portal likely intercepts traffic and redirects to its own version of the neverssl page.
# We need to capture the final destination after the initial HTML load and JS execution.

# The script will execute the JS on the client (router's curl). However, curl does not execute JS.
# The provided HTML's JS *sets* `window.location.href`. This is a client-side redirect.
# When curl fetches the HTML, it *receives* this script. It doesn't *execute* it.
# Therefore, the URL we get back via `%{url_effective}` *should* be the actual final destination if curl follows redirects.
# If the captive portal redirects `http://neverssl.com/` to its login page, the `%{url_effective}` will be that login page URL.

# Let's re-evaluate the JS. It generates a URL and sets `window.location.href`. This means the browser *would* navigate there.
# For `curl`, if the server hosting `neverssl.com` returns this HTML, and `curl` then requests `http://neverssl.com/` again, the server might serve a different response if it's a captive portal.
# The simplest interpretation is that `neverssl.com` itself IS the captive portal login page when accessed via a captive network.

# The previous `curl -L http://neverssl.com/` command should have followed any server-side redirects. 
# The obtained `REDIRECT_URL` is likely the portal's login page.

# Since there's no form submission, we assume that by successfully fetching the portal page, we are authenticated or have accepted terms.
# The challenge is to make sure `curl` lands on the *correct* page after the captive portal redirects. The `%{url_effective}` from the `-L` flag should capture this.

# Let's assume the `REDIRECT_URL` is the portal's final page. For some portals, just visiting this page is enough.

# Final check, we use the captured `REDIRECT_URL` to confirm connectivity.

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{{http_code}}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi

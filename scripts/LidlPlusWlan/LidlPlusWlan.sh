#!/bin/sh
# Fallback Script for LidlPlusWlan
# ERROR: Captured HTML was empty (0 bytes). Portal blocked or dropped the connection.

# --- WGET DEBUG LOG ---
# === Trying http://detectportal.firefox.com/ ===
# Cannot open cookies file '/tmp/portal_tmp_1782150746/cookies.txt': No such file or directory
# --2026-06-22 19:52:26--  http://detectportal.firefox.com/
# Resolving detectportal.firefox.com... failed: Try again.
# wget: unable to resolve host address 'detectportal.firefox.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://neverssl.com/ ===
# --2026-06-22 19:52:31--  http://neverssl.com/
# Resolving neverssl.com... failed: Try again.
# wget: unable to resolve host address 'neverssl.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://www.msftconnecttest.com/connecttest.txt ===
# --2026-06-22 19:52:36--  http://www.msftconnecttest.com/connecttest.txt
# Resolving www.msftconnecttest.com... 2.19.117.83, 2.19.117.78
# Connecting to www.msftconnecttest.com|2.19.117.83|:80... failed: Network unreachable.
# Connecting to www.msftconnecttest.com|2.19.117.78|:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# === Trying http://connectivitycheck.gstatic.com/generate_204 ===
# --2026-06-22 19:52:36--  http://connectivitycheck.gstatic.com/generate_204
# Resolving connectivitycheck.gstatic.com... failed: Try again.
# wget: unable to resolve host address 'connectivitycheck.gstatic.com'
# Converted links in 0 files in 0 seconds.
# === Trying http:/// ===
# http:///: Invalid host name.
# Converted links in 0 files in 0 seconds.
# 
exit 1

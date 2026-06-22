#!/bin/sh
# Fallback Script for WIFI
# ERROR: Captured HTML was empty (0 bytes). Portal blocked or dropped the connection.

# --- WGET DEBUG LOG ---
# === Trying http://detectportal.firefox.com/ ===
# Cannot open cookies file '/tmp/portal_tmp_1782130995/cookies.txt': No such file or directory
# --2026-06-22 14:23:15--  http://detectportal.firefox.com/
# Resolving detectportal.firefox.com... failed: Try again.
# wget: unable to resolve host address 'detectportal.firefox.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://neverssl.com/ ===
# --2026-06-22 14:23:20--  http://neverssl.com/
# Resolving neverssl.com... failed: Try again.
# wget: unable to resolve host address 'neverssl.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://www.msftconnecttest.com/connecttest.txt ===
# --2026-06-22 14:23:25--  http://www.msftconnecttest.com/connecttest.txt
# Resolving www.msftconnecttest.com... failed: Try again.
# wget: unable to resolve host address 'www.msftconnecttest.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://connectivitycheck.gstatic.com/generate_204 ===
# --2026-06-22 14:23:30--  http://connectivitycheck.gstatic.com/generate_204
# Resolving connectivitycheck.gstatic.com... 142.251.20.94
# Connecting to connectivitycheck.gstatic.com|142.251.20.94|:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# === Trying http:/// ===
# http:///: Invalid host name.
# Converted links in 0 files in 0 seconds.
# 
exit 1

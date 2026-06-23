#!/bin/sh
# Fallback Script for Telekom
# ERROR: Captured HTML was empty (0 bytes). Portal blocked or dropped the connection.

# --- WGET DEBUG LOG ---
# === Trying http://detectportal.firefox.com/ ===
# Cannot open cookies file '/tmp/portal_tmp_1782212785/cookies.txt': No such file or directory
# --2026-06-23 13:06:25--  http://detectportal.firefox.com/
# Resolving detectportal.firefox.com... failed: Try again.
# wget: unable to resolve host address 'detectportal.firefox.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://neverssl.com/ ===
# --2026-06-23 13:06:30--  http://neverssl.com/
# Resolving neverssl.com... failed: Try again.
# wget: unable to resolve host address 'neverssl.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://www.msftconnecttest.com/connecttest.txt ===
# --2026-06-23 13:06:35--  http://www.msftconnecttest.com/connecttest.txt
# Resolving www.msftconnecttest.com... failed: Try again.
# wget: unable to resolve host address 'www.msftconnecttest.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://connectivitycheck.gstatic.com/generate_204 ===
# --2026-06-23 13:06:40--  http://connectivitycheck.gstatic.com/generate_204
# Resolving connectivitycheck.gstatic.com... failed: Try again.
# wget: unable to resolve host address 'connectivitycheck.gstatic.com'
# Converted links in 0 files in 0 seconds.
# === Trying http:/// ===
# http:///: Invalid host name.
# Converted links in 0 files in 0 seconds.
# 
exit 1

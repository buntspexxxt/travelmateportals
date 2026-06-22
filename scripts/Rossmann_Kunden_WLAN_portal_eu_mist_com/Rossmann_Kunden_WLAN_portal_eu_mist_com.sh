#!/bin/sh
# Fallback Script for Rossmann_Kunden_WLAN_portal_eu_mist_com
# ERROR: Captured HTML was empty (0 bytes). Portal blocked or dropped the connection.

# --- WGET DEBUG LOG ---
# === Trying http://detectportal.firefox.com/ ===
# Cannot open cookies file '/tmp/portal_tmp_1782124751/cookies.txt': No such file or directory
# --2026-06-22 12:39:11--  http://detectportal.firefox.com/
# Resolving detectportal.firefox.com... 34.107.221.82
# Connecting to detectportal.firefox.com|34.107.221.82|:80... failed: Operation timed out.
# Retrying.
# 
# --2026-06-22 12:39:27--  (try: 2)  http://detectportal.firefox.com/
# Connecting to detectportal.firefox.com|34.107.221.82|:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# === Trying http://neverssl.com/ ===
# --2026-06-22 12:39:27--  http://neverssl.com/
# Resolving neverssl.com... failed: Try again.
# wget: unable to resolve host address 'neverssl.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://www.msftconnecttest.com/connecttest.txt ===
# --2026-06-22 12:39:32--  http://www.msftconnecttest.com/connecttest.txt
# Resolving www.msftconnecttest.com... failed: Try again.
# wget: unable to resolve host address 'www.msftconnecttest.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://connectivitycheck.gstatic.com/generate_204 ===
# --2026-06-22 12:39:37--  http://connectivitycheck.gstatic.com/generate_204
# Resolving connectivitycheck.gstatic.com... failed: Try again.
# wget: unable to resolve host address 'connectivitycheck.gstatic.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://172.20.0.3/ ===
# --2026-06-22 12:39:42--  http://172.20.0.3/
# Connecting to 172.20.0.3:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# 
exit 1

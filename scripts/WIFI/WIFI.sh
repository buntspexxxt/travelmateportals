#!/bin/sh
# Fallback Script for WIFI
# ERROR: Captured HTML was empty (0 bytes). Portal blocked or dropped the connection.

# --- WGET DEBUG LOG ---
# === Trying http://detectportal.firefox.com/ ===
# Cannot open cookies file '/tmp/portal_tmp_1782137590/cookies.txt': No such file or directory
# --2026-06-22 16:13:10--  http://detectportal.firefox.com/
# Resolving detectportal.firefox.com... 34.107.221.82
# Connecting to detectportal.firefox.com|34.107.221.82|:80... connected.
# HTTP request sent, awaiting response... 200 OK
# Length: 8 [application/octet-stream]
# Saving to: '/tmp/portal_tmp_1782137590/portal/detectportal.firefox.com/index.html'
# 
#      0K                                                       100%  253K=0s
# 
# 2026-06-22 16:13:11 (253 KB/s) - '/tmp/portal_tmp_1782137590/portal/detectportal.firefox.com/index.html' saved [8/8]
# 
# FINISHED --2026-06-22 16:13:11--
# Total wall clock time: 0.1s
# Downloaded: 1 files, 8 in 0s (253 KB/s)
# Converted links in 0 files in 0 seconds.
# === Trying http://neverssl.com/ ===
# --2026-06-22 16:13:11--  http://neverssl.com/
# Resolving neverssl.com... 34.223.124.45
# Connecting to neverssl.com|34.223.124.45|:80... failed: Operation timed out.
# Retrying.
# 
# --2026-06-22 16:13:27--  (try: 2)  http://neverssl.com/
# Connecting to neverssl.com|34.223.124.45|:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# === Trying http://www.msftconnecttest.com/connecttest.txt ===
# --2026-06-22 16:13:27--  http://www.msftconnecttest.com/connecttest.txt
# Resolving www.msftconnecttest.com... failed: Try again.
# wget: unable to resolve host address 'www.msftconnecttest.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://connectivitycheck.gstatic.com/generate_204 ===
# --2026-06-22 16:13:32--  http://connectivitycheck.gstatic.com/generate_204
# Resolving connectivitycheck.gstatic.com... 216.58.207.35
# Connecting to connectivitycheck.gstatic.com|216.58.207.35|:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# === Trying http://192.168.44.1/ ===
# --2026-06-22 16:13:32--  http://192.168.44.1/
# Connecting to 192.168.44.1:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# 
exit 1

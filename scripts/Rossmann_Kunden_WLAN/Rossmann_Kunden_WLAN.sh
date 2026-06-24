#!/bin/sh
# Fallback Script for Rossmann_Kunden_WLAN
# ERROR: Captured HTML was empty (0 bytes). Portal blocked or dropped the connection.

# --- WGET DEBUG LOG ---
# === Trying http://detectportal.firefox.com/success.txt ===
# --2026-06-24 17:13:31--  http://detectportal.firefox.com/success.txt
# Resolving detectportal.firefox.com... 34.107.221.82
# Connecting to detectportal.firefox.com|34.107.221.82|:80... connected.
# HTTP request sent, awaiting response... 200 OK
# Length: 8 [text/plain]
# Saving to: '/tmp/portal_tmp_1782314011/portal/detectportal.firefox.com/success.txt'
# 
#      0K                                                       100%  200K=0s
# 
# 2026-06-24 17:13:31 (200 KB/s) - '/tmp/portal_tmp_1782314011/portal/detectportal.firefox.com/success.txt' saved [8/8]
# 
# FINISHED --2026-06-24 17:13:31--
# Total wall clock time: 0.08s
# Downloaded: 1 files, 8 in 0s (200 KB/s)
# Converted links in 0 files in 0 seconds.
# === Trying http://www.msftconnecttest.com/connecttest.txt ===
# --2026-06-24 17:13:31--  http://www.msftconnecttest.com/connecttest.txt
# Resolving www.msftconnecttest.com... 23.194.190.200, 23.194.190.216
# Connecting to www.msftconnecttest.com|23.194.190.200|:80... connected.
# HTTP request sent, awaiting response... 200 OK
# Length: 22 [text/plain]
# Saving to: '/tmp/portal_tmp_1782314011/portal/www.msftconnecttest.com/connecttest.txt'
# 
#      0K                                                       100%  691K=0s
# 
# 2026-06-24 17:13:31 (691 KB/s) - '/tmp/portal_tmp_1782314011/portal/www.msftconnecttest.com/connecttest.txt' saved [22/22]
# 
# FINISHED --2026-06-24 17:13:31--
# Total wall clock time: 0.1s
# Downloaded: 1 files, 22 in 0s (691 KB/s)
# Converted links in 0 files in 0 seconds.
# === Trying http://connectivitycheck.gstatic.com/generate_204 ===
# --2026-06-24 17:13:31--  http://connectivitycheck.gstatic.com/generate_204
# Resolving connectivitycheck.gstatic.com... 142.250.154.94
# Connecting to connectivitycheck.gstatic.com|142.250.154.94|:80... connected.
# HTTP request sent, awaiting response... 204 No Content
# 2026-06-24 17:13:31 (0.00 B/s) - '/tmp/portal_tmp_1782314011/portal/connectivitycheck.gstatic.com/generate_204' saved [0]
# 
# Converted links in 0 files in 0 seconds.
# === Trying http://10.154.124.1/ ===
# --2026-06-24 17:13:31--  http://10.154.124.1/
# Connecting to 10.154.124.1:80... failed: Operation timed out.
# Retrying.
# 
# --2026-06-24 17:14:17--  (try: 2)  http://10.154.124.1/
# Connecting to 10.154.124.1:80... failed: Operation timed out.
# Giving up.
# 
# Converted links in 0 files in 0 seconds.
# 
exit 1

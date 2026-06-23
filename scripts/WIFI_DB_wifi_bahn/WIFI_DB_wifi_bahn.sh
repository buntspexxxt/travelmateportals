#!/bin/sh
# Fallback Script for WIFI_DB_wifi_bahn
# ERROR: Captured HTML was empty (0 bytes). Portal blocked or dropped the connection.

# --- WGET DEBUG LOG ---
# === Trying http://detectportal.firefox.com/ ===
# Cannot open cookies file '/tmp/portal_tmp_1782196621/cookies.txt': No such file or directory
# --2026-06-23 08:37:01--  http://detectportal.firefox.com/
# Resolving detectportal.firefox.com... 34.107.221.82
# Connecting to detectportal.firefox.com|34.107.221.82|:80... connected.
# HTTP request sent, awaiting response... 302 Found
# Location: https://wifi.bahn.de/ [following]
# --2026-06-23 08:37:01--  https://wifi.bahn.de/
# Resolving wifi.bahn.de... 185.109.152.241
# Connecting to wifi.bahn.de|185.109.152.241|:443... connected.
# OpenSSL: error:0A000152:SSL routines::unsafe legacy renegotiation disabled
# Unable to establish SSL connection.
# Converted links in 0 files in 0 seconds.
# === Trying http://neverssl.com/ ===
# --2026-06-23 08:37:01--  http://neverssl.com/
# Resolving neverssl.com... 34.223.124.45
# Connecting to neverssl.com|34.223.124.45|:80... connected.
# HTTP request sent, awaiting response... 302 Found
# Location: https://wifi.bahn.de/ [following]
# --2026-06-23 08:37:22--  https://wifi.bahn.de/
# Resolving wifi.bahn.de... 185.109.152.241
# Connecting to wifi.bahn.de|185.109.152.241|:443... connected.
# OpenSSL: error:0A000152:SSL routines::unsafe legacy renegotiation disabled
# Unable to establish SSL connection.
# Converted links in 0 files in 0 seconds.
# === Trying http://www.msftconnecttest.com/connecttest.txt ===
# --2026-06-23 08:37:22--  http://www.msftconnecttest.com/connecttest.txt
# Resolving www.msftconnecttest.com... 184.86.251.145, 184.86.251.150
# Connecting to www.msftconnecttest.com|184.86.251.145|:80... connected.
# HTTP request sent, awaiting response... 302 Found
# Location: https://wifi.bahn.de/ [following]
# --2026-06-23 08:37:22--  https://wifi.bahn.de/
# Resolving wifi.bahn.de... 185.109.152.241
# Connecting to wifi.bahn.de|185.109.152.241|:443... connected.
# OpenSSL: error:0A000152:SSL routines::unsafe legacy renegotiation disabled
# Unable to establish SSL connection.
# Converted links in 0 files in 0 seconds.
# === Trying http://connectivitycheck.gstatic.com/generate_204 ===
# --2026-06-23 08:37:23--  http://connectivitycheck.gstatic.com/generate_204
# Resolving connectivitycheck.gstatic.com... 142.251.20.94
# Connecting to connectivitycheck.gstatic.com|142.251.20.94|:80... connected.
# HTTP request sent, awaiting response... 302 Found
# Location: https://wifi.bahn.de/ [following]
# --2026-06-23 08:37:23--  https://wifi.bahn.de/
# Resolving wifi.bahn.de... 185.109.152.241
# Connecting to wifi.bahn.de|185.109.152.241|:443... connected.
# OpenSSL: error:0A000152:SSL routines::unsafe legacy renegotiation disabled
# Unable to establish SSL connection.
# Converted links in 0 files in 0 seconds.
# === Trying http://100.72.0.1/ ===
# --2026-06-23 08:37:23--  http://100.72.0.1/
# Connecting to 100.72.0.1:80... failed: Operation timed out.
# Retrying.
# 
# --2026-06-23 08:38:09--  (try: 2)  http://100.72.0.1/
# Connecting to 100.72.0.1:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# 
exit 1

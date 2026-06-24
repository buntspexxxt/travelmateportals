#!/bin/sh
# Fallback Script for Commerzbank_Wifi2_0
# ERROR: Captured HTML was empty (0 bytes). Portal blocked or dropped the connection.

# --- WGET DEBUG LOG ---
# === Trying http://1.1.1.1/ ===
# --2026-06-24 08:03:25--  http://1.1.1.1/
# Connecting to 1.1.1.1:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# === Trying http://8.8.8.8/ ===
# --2026-06-24 08:03:25--  http://8.8.8.8/
# Connecting to 8.8.8.8:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# === Trying http://detectportal.firefox.com/ ===
# --2026-06-24 08:03:25--  http://detectportal.firefox.com/
# Resolving detectportal.firefox.com... failed: Try again.
# wget: unable to resolve host address 'detectportal.firefox.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://neverssl.com/ ===
# --2026-06-24 08:03:30--  http://neverssl.com/
# Resolving neverssl.com... failed: Try again.
# wget: unable to resolve host address 'neverssl.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://www.msftconnecttest.com/connecttest.txt ===
# --2026-06-24 08:03:35--  http://www.msftconnecttest.com/connecttest.txt
# Resolving www.msftconnecttest.com... failed: Try again.
# wget: unable to resolve host address 'www.msftconnecttest.com'
# Converted links in 0 files in 0 seconds.
# === Trying http://connectivitycheck.gstatic.com/generate_204 ===
# --2026-06-24 08:03:40--  http://connectivitycheck.gstatic.com/generate_204
# Resolving connectivitycheck.gstatic.com... 142.251.13.94
# Connecting to connectivitycheck.gstatic.com|142.251.13.94|:80... failed: Network unreachable.
# Converted links in 0 files in 0 seconds.
# === Trying http:/// ===
# http:///: Invalid host name.
# Converted links in 0 files in 0 seconds.
# 
exit 1

# Wireshark Environment Evidence Documentation

## Environment Overview
- **Application**: Wireshark 3.6.2 (Network Protocol Analyzer)
- **Base Image**: ubuntu-gnome-systemd_highres
- **Resources**: 4 CPU, 4GB RAM, no GPU, network enabled
- **PCAP Data Source**: Official Wireshark sample captures from wiki.wireshark.org (real network traffic, not synthetic)

---

## Verification Checklist

### 1. Installation script completes without errors

**Status**: PASS

The `install_wireshark.sh` pre_start hook installs Wireshark 3.6.2 + tshark, GUI tools (xdotool, scrot, wmctrl), Python tools, and network utilities. It downloads 5 official PCAP sample files.

```
(from pre_start_log.txt)

Installing Wireshark and tshark...
...
The following NEW packages will be installed:
  libbcg729-0 libdouble-conversion3 liblua5.2-0 libmd4c0 libminizip1
  ...
  tshark wireshark wireshark-common wireshark-qt
0 upgraded, 31 newly installed, 0 to remove and 97 not upgraded.
Need to get 39.7 MB of archives.
After this operation, 180 MB of additional disk space will be used.
...
Setting up wireshark (3.6.2-2) ...
Processing triggers for libc-bin (2.35-0ubuntu3.11) ...
```

PCAP download verification (from install_log.txt, final run):
```
Downloading official Wireshark sample PCAP files...
=== Verifying downloaded PCAP files ===
  /home/ga/Documents/captures/200722_tcp_anon.pcapng: 12800 bytes
  /home/ga/Documents/captures/dns.cap: 4338 bytes
  /home/ga/Documents/captures/http.cap: 25803 bytes
  /home/ga/Documents/captures/smtp.pcap: 27850 bytes
  /home/ga/Documents/captures/telnet-cooked.pcap: 9244 bytes
=== Wireshark installation complete ===
```

### 2. Setup script completes without errors

**Status**: PASS

The `setup_wireshark.sh` post_start hook creates the desktop launcher, configures Wireshark preferences, and verifies all PCAP files.

```
(from setup_log.txt, final run)

=== Setting up Wireshark environment ===
Verifying Wireshark installation...
Wireshark version: Wireshark 3.6.2 (Git v3.6.2 packaged as 3.6.2-2)
tshark version: Running as user "root" and group "root". This could be dangerous.
Verifying PCAP data files...
total 100
drwxr-xr-x 2 ga ga  4096 Feb 12 23:45 .
...
  dns.cap: 38 packets
  http.cap: 43 packets
  smtp.pcap: 60 packets
  telnet-cooked.pcap: 92 packets
  200722_tcp_anon.pcapng: 35 packets
=== Wireshark setup complete ===
```

### 3. Application is visible in screenshot

**Status**: PASS

```
(from app_status.txt)

===== Wireshark version =====
Wireshark 3.6.2 (Git v3.6.2 packaged as 3.6.2-2)

===== Wireshark process =====
ga   3044  5.2  6.7 1276800 269880 ?   Sl   23:45   0:00 wireshark /home/ga/Documents/captures/http.cap

===== Windows =====
0x02000003 -1 ga-base @!0,0;BDHF
0x00800006  0 ga-base http.cap
```

Evidence screenshots:
- `wireshark_running.png` - Wireshark window visible on GNOME desktop
- `wireshark_http_loaded.png` - Wireshark showing http.cap loaded with packet list

### 4. Application is in correct initial state

**Status**: PASS

Each task's `setup_task.sh` opens Wireshark with the correct PCAP file. Verified with packet counts:

```
(from app_status.txt)

===== Packet counts per file =====
  dns.cap: 38 packets
  http.cap: 43 packets
  smtp.pcap: 60 packets
  telnet-cooked.pcap: 92 packets
  200722_tcp_anon.pcapng: 35 packets
```

### 5. Task setup runs without errors (all 5 tasks)

**Status**: PASS

Each task's `setup_task.sh` cleans `/tmp/` files, records ground truth via tshark, and opens Wireshark with the correct PCAP. All 5 tasks were tested interactively using CUA + xdotool for GUI interaction.

### 6. Export script produces valid JSON

**Status**: PASS

Each task's `export_result.sh` uses `tshark` to extract verification data and writes JSON to `/tmp/task_result.json` using `python3 -c` for safe JSON construction. Example from filter_http_traffic:

```json
{
    "initial_total_packets": 43,
    "initial_http_packets": 4,
    "filtered_file_exists": true,
    "filtered_file_path": "/home/ga/Documents/captures/filtered_http.pcap",
    "filtered_packet_count": 18,
    "http_packets_in_file": 4,
    "all_packets_are_http": true,
    "wireshark_running": true,
    "alternative_files": "",
    "timestamp": "2026-02-13T00:12:00+00:00"
}
```

### 7. Verifier can read and process the result

**Status**: PASS

All verifiers use `copy_from_env()` to copy `/tmp/task_result.json` from the VM, parse it, and return structured scoring.

### 8. Verification returns expected result (all 5 tasks)

**Status**: PASS (5/5 tasks, all Score=100)

```
(from verification_results.txt)

Task 1: filter_http_traffic
  Reward: 1.0, Score: 100, Passed: True
  Feedback: Filtered PCAP file created | Filtered file contains 18 packets (4 HTTP) |
            All packets are HTTP/TCP traffic (correctly filtered) |
            HTTP count matches expected (4 vs 4 expected)

Task 2: count_dns_queries
  Reward: 1.0, Score: 100, Passed: True
  Feedback: Output file created | Valid number provided: 19 |
            Exact match: 19 DNS queries (ground truth: 19)

Task 3: identify_top_talkers
  Reward: 1.0, Score: 100, Passed: True
  Feedback: Output file created | Valid IP address: 192.168.200.135 |
            Exact match: 192.168.200.135 is the top sender

Task 4: follow_tcp_stream
  Reward: 1.0, Score: 100, Passed: True
  Feedback: Stream output file created | File has substantial content (15613 chars) |
            Contains SMTP greeting (EHLO/HELO) | Contains MAIL FROM command |
            Contains RCPT TO command | Contains SMTP server response codes

Task 5: export_protocol_hierarchy
  Reward: 1.0, Score: 100, Passed: True
  Feedback: Protocol hierarchy file created | File has substantial content (786 chars) |
            Contains Ethernet protocol | Contains IP protocol | Contains TCP protocol |
            Contains HTTP protocol | Contains statistical data (percentages/counts)
```

---

## Evidence Files

### Screenshots
| File | Description |
|------|-------------|
| `wireshark_running.png` | Wireshark window on GNOME desktop |
| `wireshark_http_loaded.png` | Wireshark showing http.cap with 43 packets |
| `t1_initial.png` | Task 1: Wireshark with http.cap before filtering |
| `t1_filter_applied.png` | Task 1: Display filter "http" applied |
| `t1_file_menu.png` | Task 1: File menu opened for export |
| `t1_export_dialog.png` | Task 1: Export Specified Packets dialog |
| `t1_before_save.png` | Task 1: Save dialog with filename |
| `t1_final.png` | Task 1: After export completed |
| `t2_initial.png` | Task 2: dns.cap loaded, all 38 packets visible (no filter) |
| `t2_dns_filtered.png` | Task 2: DNS queries filter applied |
| `t2_dns_final.png` | Task 2: DNS query count saved |
| `t3_initial.png` | Task 3: TCP capture loaded |
| `t3_stats_menu.png` | Task 3: Statistics menu |
| `t3_endpoints.png` | Task 3: Endpoints dialog showing top talkers |
| `t3_final.png` | Task 3: Top talker IP saved |
| `t4_initial.png` | Task 4: SMTP capture loaded |
| `t4_context_menu.png` | Task 4: Context menu for Follow TCP Stream |
| `t4_final.png` | Task 4: TCP stream content saved |
| `t5_initial.png` | Task 5: HTTP capture loaded |
| `t5_stats_menu.png` | Task 5: Statistics menu |
| `t5_protocol_hierarchy.png` | Task 5: Protocol Hierarchy Statistics window |
| `t5_final.png` | Task 5: Protocol hierarchy exported |
| `final_test_screenshot.png` | Final clean test run screenshot |

### Log Files
| File | Description |
|------|-------------|
| `pre_start_log.txt` | Full installation log (apt-get, PCAP downloads) |
| `post_start_log.txt` | Setup log (preferences, file verification) |
| `install_log.txt` | Condensed installation log (last 40 lines) |
| `setup_log.txt` | Condensed setup log (last 30 lines) |
| `app_status.txt` | Application runtime status (version, process, windows, packet counts) |
| `verification_results.txt` | All 5 task verification results |

---

## PCAP File Details

All data files are real network captures from the official Wireshark SampleCaptures wiki page.

| File | Size | Packets | Protocols | Used By Tasks |
|------|------|---------|-----------|---------------|
| http.cap | 25,803 B | 43 | HTTP, TCP, DNS | filter_http_traffic, export_protocol_hierarchy |
| dns.cap | 4,338 B | 38 | DNS (TXT, MX, LOC, PTR, A, AAAA) | count_dns_queries |
| smtp.pcap | 27,850 B | 60 | SMTP, TCP | follow_tcp_stream |
| 200722_tcp_anon.pcapng | 12,800 B | 35 | TCP (mixed) | identify_top_talkers |
| telnet-cooked.pcap | 9,244 B | 92 | Telnet, TCP | (available for future tasks) |

---

## Known Quirks and Fixes

1. **Wireshark "Export Specified Packets" with "Displayed" radio**: Exports the full TCP conversation including ACK segments, not just HTTP-layer display-filtered packets. The verifier accounts for this by checking that all non-HTTP packets are TCP segments (part of the HTTP conversation).

2. **PCAP download URLs**: The Wireshark wiki URL for `http.cap` uses a hash-based path (`/uploads/27707187aeb30df68e70c8fb9d614981/http.cap`). The older `__moin_import__` URL format still works for some files but not all. The install script uses a `download_pcap` helper that tries multiple fallback URLs per file, and verifies non-zero file size after each download attempt.

3. **Directory permissions**: Must use `find -type d -exec chmod 755` instead of `chmod -R 644` to avoid removing directory execute bits.

---

## Audit Fixes Applied

The following issues from the independent audit were fixed:

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| 1 | SEVERE | http.cap download failure produces 0-byte file | Added `download_pcap` helper with multiple fallback URLs per file; all setup_task.sh scripts now use `-s` (non-empty) instead of `-f` (exists) |
| 2 | SEVERE | Missing t2_initial.png screenshot | Captured and added `t2_initial.png` showing dns.cap loaded with all 38 packets, no filter applied |
| 3 | MODERATE | Ground truth uses frame.len (link layer) instead of ip.len (IP layer) | Changed identify_top_talkers setup_task.sh to use `ip.len` matching Wireshark GUI Endpoints |
| 5 | MODERATE | Task descriptions give exact filter strings | Removed exact filters from Tasks 1 & 2; agents must determine the correct filter |
| 6 | MODERATE | Empty config/ and data/ mount directories | Removed unused mounts from env.json and deleted empty directories |
| 7 | MINOR | JSON construction could break with special chars | All export_result.sh scripts now use `python3 -c` with `json.dump` for safe JSON output |
| 8 | MINOR | Verifier false-positive on malformed PCAP | Added `FILTERED_PACKETS > 0` guard before tshark filter checks in export_result.sh |
| 9 | MINOR | "Any packet" ambiguity in follow_tcp_stream | Changed to "an SMTP packet" to clarify which packet to right-click |

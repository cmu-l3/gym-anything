# Telnet Credential Extraction

## Overview
Incident response task. The agent must reconstruct a Telnet session from a packet capture to extract login credentials, identify the remote system, and document commands typed during the session.

## Domain Context
Incident responders and security analysts frequently analyze cleartext protocol captures to determine what actions were taken on a compromised system. Telnet sessions transmit credentials and commands in plaintext, making packet analysis a critical forensic tool.

## Goal
Analyze telnet-cooked.pcap and produce an incident report containing:
1. Login username
2. Login password
3. System banner/OS identification
4. All commands typed post-login
5. Total Telnet packet count

## Difficulty: Hard
- Agent must reconstruct character-by-character Telnet data
- No UI hints provided
- Requires TCP stream following, display filters, and protocol inspection
- Must distinguish client-side data (commands) from server-side data (responses)

## Data
- Input: telnet-cooked.pcap (92 packets, Telnet session)
- Output: /home/ga/Documents/captures/telnet_incident_report.txt

# Network Baseline Audit

## Overview
Network architecture task. The agent must analyze a merged multi-protocol capture to produce a comprehensive network baseline report documenting all protocols, endpoints, ports, retransmissions, and traffic volumes.

## Domain Context
Network architects perform baseline audits to establish normal traffic patterns before deploying new infrastructure or security controls. This requires analyzing a mixed-protocol capture using multiple Wireshark statistics features (Protocol Hierarchy, Endpoints, Conversations, Expert Info).

## Goal
Analyze a merged capture (baseline_audit.pcapng) and produce a baseline report containing:
1. All protocols observed
2. All unique IP endpoints
3. All destination ports contacted
4. TCP retransmission count
5. Total packet count and byte volume

## Difficulty: Hard
- Uses a merged capture (HTTP + DNS + TCP) with diverse protocol mix
- Agent must use multiple Statistics dialogs and display filters
- Must analyze retransmissions (Expert Info or tcp.analysis filters)
- Requires extracting both summary statistics and detailed inventories
- Distinct starting data created by mergecap at setup time

## Data
- Input: baseline_audit.pcapng (merged from http.cap + dns.cap + 200722_tcp_anon.pcapng)
- Output: /home/ga/Documents/captures/baseline_audit_report.txt

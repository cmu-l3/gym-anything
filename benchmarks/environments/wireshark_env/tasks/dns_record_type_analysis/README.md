# DNS Record Type Analysis

## Overview
Network engineering audit task. The agent must analyze DNS traffic to produce a compliance-ready audit report documenting all queried domains, record types, DNS servers, and query/response statistics.

## Domain Context
Network engineers and security analysts audit DNS traffic to detect anomalies, verify that only approved DNS servers are in use, understand query patterns, and identify unusual record types (TXT, LOC) that might indicate data exfiltration or misconfiguration.

## Goal
Analyze dns.cap and produce an audit report containing:
1. All unique domain names queried
2. All DNS record types with per-type query counts
3. DNS server IP address(es)
4. Total query packet count
5. Total response packet count

## Difficulty: Hard
- dns.cap contains multiple record types (A, AAAA, MX, TXT, LOC, PTR) requiring the agent to identify each
- Agent must distinguish queries from responses using protocol flags
- Requires multiple display filters and/or Statistics > DNS
- Must produce a structured report with per-type breakdowns

## Data
- Input: dns.cap (38 packets, mixed DNS record types)
- Output: /home/ga/Documents/captures/dns_audit_report.txt

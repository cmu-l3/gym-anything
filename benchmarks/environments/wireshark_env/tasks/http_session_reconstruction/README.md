# HTTP Session Reconstruction

## Overview
Network security analysis task. The agent must reconstruct a complete HTTP browsing session from a packet capture, extracting all request URIs, server information, response codes, and client identification.

## Domain Context
Security analysts and network architects analyze HTTP traffic to understand browsing patterns, detect suspicious activity, and audit web application usage. Reconstructing sessions from raw packet data requires proficiency with display filters, HTTP-specific inspection, and statistics features.

## Goal
Analyze http.cap and produce a session analysis report containing:
1. All HTTP request URIs
2. Web server IP address
3. All HTTP response status codes
4. Client User-Agent string
5. Total HTTP request packet count

## Difficulty: Hard
- Agent must use multiple Wireshark features (HTTP filters, packet details, Statistics)
- No UI navigation provided
- Must correlate requests with responses
- Requires understanding HTTP protocol structure

## Data
- Input: http.cap (43 packets, HTTP web traffic)
- Output: /home/ga/Documents/captures/http_analysis_report.txt

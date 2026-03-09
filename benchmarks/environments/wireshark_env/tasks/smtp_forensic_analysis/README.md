# SMTP Forensic Analysis

## Overview
Security analyst incident investigation task. The agent must analyze SMTP traffic from a packet capture to extract forensic evidence about an email sent from a compromised workstation.

## Domain Context
Information security analysts routinely use Wireshark to investigate email-based incidents — phishing campaigns, data exfiltration via email, or unauthorized outbound communication. Extracting sender, recipient, subject, and server information from SMTP captures is a core forensic workflow.

## Goal
Analyze smtp.pcap and produce a forensic report containing 5 independent pieces of information:
1. Sender email address (MAIL FROM)
2. Recipient email address (RCPT TO)
3. Email subject line (from DATA headers)
4. SMTP server banner/software
5. Total SMTP packet count

## Difficulty: Hard
- Agent must discover how to extract each piece of information
- No UI navigation hints provided
- Requires using multiple Wireshark features (stream following, display filters, packet inspection)
- Must produce a structured text report

## Verification
Each item is independently scored. The verifier checks for the presence of correct values in the agent's report by comparing against ground truth computed by tshark.

## Data
- Input: smtp.pcap (60 packets, SMTP email conversation)
- Output: /home/ga/Documents/captures/smtp_forensic_report.txt

# Task: DevTools Network Performance Audit

## Domain Context
Web developers regularly use browser DevTools to audit network performance across multiple sites. This is a core professional skill for optimizing page load times, diagnosing latency issues, and producing client-facing audit reports. The task reflects real consulting work where a developer must evaluate third-party websites and produce an actionable document.

## Goal
Audit the network performance of three news websites (BBC, Reuters, The Guardian) using Edge DevTools, and produce a professional audit report at `/home/ga/Desktop/network_audit_report.txt`.

## What the Agent Must Figure Out
- That Edge DevTools are opened via F12 or right-click → Inspect
- That the Network panel must be active and recording before reloading the page
- How to sort by transfer size to find the largest resources
- How to read the request count from the Network panel summary bar
- How to open each site in a tab and capture its data independently
- How to write a structured professional report

## Success Criteria
The task is considered complete when:
1. `/home/ga/Desktop/network_audit_report.txt` exists and was written after the task started
2. The browser history shows visits to bbc.com, reuters.com, and theguardian.com
3. The report mentions all three site domains
4. The report contains file size values (numbers with KB/MB units)
5. The report contains request count information

## Verification Strategy
- **History check**: Query Edge's SQLite History database for URL visits to the 3 target domains
- **Report existence**: Check file exists at expected path, modified after task start
- **Report content**: Regex search for domain names, size values (KB/MB), and request count patterns
- **File size**: Report must be > 500 bytes (proxy for completeness)

## Scoring Breakdown (100 points)
- Report exists and was written after task start: 15 points
- BBC.com visited (history) AND mentioned in report: 15 points
- Reuters.com visited (history) AND mentioned in report: 15 points
- TheGuardian.com visited (history) AND mentioned in report: 15 points
- Report contains file size values (KB/MB numbers): 20 points
- Report contains request count values (N requests/resources): 10 points
- Report is comprehensive (> 800 bytes): 10 points

**Pass threshold**: 65 points

## Why This Is Hard
1. Agent must know to open DevTools (F12 or right-click menu)
2. Agent must understand the Network panel requires page load to capture requests
3. Agent must know to sort by size to find largest resources
4. Agent must do this for three different sites (multi-step, multi-tab)
5. Agent must synthesize findings into a professional report
6. No step-by-step instructions are given — only the goal

## Edge Cases
- If Edge blocks network capture via DevTools (unlikely), the agent must find an alternative
- If a site is slow to load, the agent must wait for network activity to settle
- The agent must reload each page with Network panel open to capture all requests

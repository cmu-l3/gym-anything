# Task: Configure Domain Resource Limits and Quotas

## Overview
A web administrator needs to enforce resource limits on the greenvalley.test virtual server to prevent resource abuse and ensure fair hosting. This involves configuring disk quotas, bandwidth limits, and maximum counts for mailboxes, aliases, and databases — all through the Virtualmin control panel.

## Domain Context
Web administrators routinely configure per-domain resource limits to:
- Prevent any single client from consuming all server resources
- Enforce hosting plan tiers (shared hosting packages)
- Protect against runaway disk usage or bandwidth spikes

## Goal
Configure the following limits for greenvalley.test:
1. Disk quota: 500 MB
2. Bandwidth limit: 5 GB/month
3. Max mailboxes: 10
4. Max aliases: 20
5. Max databases: 3

## Why This Is Hard
- These settings are spread across multiple configuration areas in Virtualmin
- The agent must discover which Virtualmin pages contain quota/limit settings
- Some limits are in "Edit Virtual Server", others in "Resource Limits"
- The agent must understand the difference between server quota and user quota
- No step-by-step UI instructions are provided

## Verification Strategy
Each limit is checked independently via the Virtualmin CLI:
- `virtualmin list-domains --domain greenvalley.test --multiline` for quotas and limits
- Direct quota checks for disk quotas
- Bandwidth and count limits from domain configuration

## Ground Truth
All values are from task.json metadata. Verification uses ±10% tolerance for numeric values.

## Edge Cases and Potential Issues
- `quota=0` in Virtualmin means **unlimited**, not zero — the verifier treats 0 as "not set"
- Disk quota and bandwidth use different units internally (kB vs bytes); the verifier auto-detects
- Settings are spread across "Edit Virtual Server" (quota, bandwidth) and "Resource Limits" (mailbox/alias/database caps) — they are NOT on one page
- Agent may confuse server-wide quotas with per-domain quotas
- Bandwidth limit may show different units in the UI (MB vs GB) depending on Virtualmin version
- The ±10% tolerance in the verifier accounts for kB/MB rounding differences (e.g., 500MB = 512000kB = 488.28MB in some tools)

## Schema Reference
Virtualmin stores these in the domain's configuration:
- Disk quota: `quota` field (in kB)
- Bandwidth: `bw_limit` field (in bytes)
- Max mailboxes: `max_mailboxes` field
- Max aliases: `max_aliases` field
- Max databases: `max_dbs` field

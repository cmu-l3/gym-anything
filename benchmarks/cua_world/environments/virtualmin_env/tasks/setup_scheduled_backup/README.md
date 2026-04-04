# Task: Configure Scheduled Backup for All Domains

## Overview
A web administrator needs to set up automated backups for all hosted domains. This involves configuring Virtualmin's scheduled backup system with specific destination, schedule, feature selection, and retention policy.

## Domain Context
Backup management is one of the most critical web administrator tasks:
- Regular backups protect against data loss
- Multi-domain backups must cover all hosted sites
- Retention policies prevent disk exhaustion
- Feature selection ensures all important data is captured

## Goal
Create a scheduled backup that:
1. Covers all 3 domains (acmecorp.test, brightstar.test, greenvalley.test)
2. Backs up to /backup/virtualmin/
3. Runs daily
4. Includes home files, mail, MySQL, and DNS
5. Retains the 7 most recent backups

## Why This Is Hard
- The agent must find Virtualmin's scheduled backup interface
- Must configure multiple settings in one form: domain selection, destination, schedule, features, retention
- Must understand the difference between one-time and scheduled backups
- The backup directory must be created first
- Feature selection requires understanding what "dir", "mail", "mysql", "dns" correspond to in the UI
- 5 independent verification criteria

## Edge Cases and Potential Issues
- Agent may create a **one-time backup** instead of a **scheduled backup** — the verifier only checks scheduled backups
- The `/backup/virtualmin/` directory does not exist by default and must be created first
- "All domains" can be selected by checking all 3 individually or by selecting "All virtual servers" — both are valid
- Feature names in the UI differ from internal names: "Home directory" → `dir`, "Mail files" → `mail`, etc.
- Daily schedule in Virtualmin means the backup runs once per day — some agents may misconfigure hourly/weekly
- Retention count of 7 means "keep the 7 most recent backups" — not "keep backups for 7 days"
- The export script parses both `--multiline` and `--json` output formats from `virtualmin list-scheduled-backups`
- If multiple scheduled backups exist, the verifier checks all of them and uses the best match

## Verification Strategy
- Check if a scheduled backup exists via `virtualmin list-scheduled-backups`
- Verify it covers all 3 domains
- Verify destination is /backup/virtualmin/
- Verify schedule is daily
- Verify features include the required set
- Verify retention is set to 7

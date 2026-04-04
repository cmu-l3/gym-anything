# Contractor Overstay Compliance Audit — December 2025

## Task Overview

ACME Corp policy restricts all contractor on-site access to a maximum of 2 hours (120 minutes).
Any contractor who remained on-site for **strictly more than 120 minutes** in December 2025 is
considered a policy violation requiring formal documentation.

You are the Security Director. Your task is to audit December 2025 contractor visit records,
identify every policy violation, and export a compliance report.

## Goal State

A file named `contractor_overstay_dec2025.csv` must be present at `/home/ga/Desktop/`
containing every contractor record from December 2025 where the total on-site duration
exceeded 2 hours (strictly > 120 minutes). The report should include visitor names, company
names, sign-in times, sign-out times, and durations.

## Credentials

- Application: Jolly LobbyTrack (already open on desktop)
- No username/password required

## What the Agent Must Discover

The agent must:
1. Navigate to visitor records for December 2025
2. Filter or identify records where Badge Type = Contractor
3. Calculate on-site durations from sign-in/sign-out times
4. Identify which contractors stayed strictly longer than 2 hours
5. Export those records to the Desktop file path specified above

**Do not include exact contractor names in this README — the agent must discover them by
analyzing the system data.**

## Success Criteria

The output file `/home/ga/Desktop/contractor_overstay_dec2025.csv` must:
- Exist at the specified path
- Contain records for **all three** December 2025 contractor policy violations
- Include sufficient company/visitor identification to confirm correct targets
- Contain time or duration information demonstrating the overstay

## Verification Strategy

1. File existence — prerequisite; score=0 if missing
2. First overstay contractor (company/name) present — 25 pts
3. Second overstay contractor (company/name) present — 25 pts
4. Third overstay contractor (company/name) present — 25 pts
5. Duration/time information present in report — 25 pts

Passing threshold: 70 points (at least 3 of 4 scored criteria)

## Schema Reference

Visitor records contain: First Name, Last Name, Company, Badge Type,
Sign In Date, Sign In Time, Sign Out Time, Host First Name, Host Last Name,
Host Department, Purpose, Email, Phone

Duration = Sign Out Time − Sign In Time (in minutes). Policy limit = 120 min.

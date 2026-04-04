# December 2025 Visitor Traffic Analysis — Badge Type & Department Breakdown

## Task Overview

At the end of each month, the Security Director reviews visitor traffic patterns to assess
physical security posture and resource allocation. The December 2025 analysis requires a
complete breakdown of visitor activity by badge type (Visitor, Contractor, Vendor) and by
host department, identifying the top three most-visited departments.

## Your Mission

You are the Security Director at ACME Corp. Generate a comprehensive December 2025 visitor
traffic analysis report that covers:
1. Total visitor count for the month
2. Breakdown by badge type (how many Visitors, Contractors, and Vendors)
3. Top 3 host departments by total visitor traffic
4. Export the complete analysis to the Desktop

## Goal State

A file named `dec2025_visitor_analysis.csv` must exist at `/home/ga/Desktop/` containing:
- Total visitor count for December 2025
- Count of each badge type (Visitor, Contractor, Vendor)
- Top three host departments by total visits with their visitor counts

## Credentials

- Application: Jolly LobbyTrack (already open)
- No username/password required

## What the Agent Must Discover

The agent must:
1. Navigate to Reports and generate a full December 2025 visitor report
2. Count or filter by each badge type (Visitor, Contractor, Vendor)
3. Group by host department and rank by visit count
4. Identify the top 3 departments (note: there are three departments tied at 3 visits each)
5. Export the summary analysis to the specified path

## Success Criteria

The file `/home/ga/Desktop/dec2025_visitor_analysis.csv` must:
- Exist at the specified path
- Reflect a total count of approximately 40 visitors for December 2025
- Show counts for badge types consistent with 16 Visitors, 12 Contractors, 12 Vendors
- Identify Marketing, Procurement, and Facilities as top departments (each with 3 visits)

## Verification Strategy

1. File existence — prerequisite; score=0 if missing
2. Total count approximately correct (38–42 range) — 25 pts
3. Badge type counts correct (Visitors ~16, Contractors ~12, Vendors ~12, within ±2) — 25 pts
4. Top departments identified (Marketing, Procurement, Facilities) — 30 pts
5. File is substantive (>200 bytes) — 20 pts

Passing threshold: 70 points

## Schema Reference

December 2025 has exactly 40 visitor records:
- Visitor badge:    16 records
- Contractor badge: 12 records
- Vendor badge:     12 records
- Total:            40 records

Top departments (tied at 3 each):
- Marketing   (3): Barbara Anderson/P&G, Thomas Martin/Facebook Meta, Dorothy Green/Walt Disney
- Procurement (3): Patricia Williams/Pfizer, Andrew Adams/Northrop Grumman, Mark Mitchell/Dow Chemical
- Facilities  (3): Matthew Rodriguez/Ford, Betty Walker/Caterpillar, Kenneth King/Honeywell

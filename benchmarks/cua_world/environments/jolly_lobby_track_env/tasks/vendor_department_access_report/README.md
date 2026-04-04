# Vendor Department Access Report — December 2025

## Task Overview

The Procurement and Facilities teams need a summary of all vendor access across ACME Corp
departments during December 2025. This report informs annual vendor contract reviews and
helps identify departments with the highest vendor traffic that may need additional
access controls.

## Your Mission

You are the Procurement Manager. Generate a vendor access analysis for December 2025 that
groups all vendor visits by host department, identifies the department with the most
vendor visits, and exports a sorted summary report.

## Goal State

A file named `vendor_dept_access_dec2025.csv` must exist at `/home/ga/Desktop/` containing
all vendor visits from December 2025, organized by host department. The report should
show which department received the most vendor visits and list all vendor companies
within each department.

## Credentials

- Application: Jolly LobbyTrack (already open)
- No username/password required

## What the Agent Must Discover

The agent must:
1. Navigate to visitor records and filter by Badge Type = Vendor AND Date = December 2025
2. Group or organize the results by host department
3. Identify the department with the highest vendor visit count
4. Export the complete vendor-by-department report to the specified Desktop path

## Success Criteria

The output file `/home/ga/Desktop/vendor_dept_access_dec2025.csv` must:
- Exist at the specified path
- Identify the top vendor-receiving department
- List the vendor companies within that top department
- Reflect the full scope of December 2025 vendor visits

## Verification Strategy

1. File existence — prerequisite; score=0 if missing
2. "Facilities" identified as the top department — 30 pts
3. All three Facilities vendors present (Ford, Caterpillar, Honeywell) — 25 pts
4. Total vendor count reflects approximately 12 vendors — 20 pts
5. File is substantive (size > 150 bytes) — 25 pts

Passing threshold: 70 points

## Schema Reference

Vendor visits: Badge Type = "Vendor"
Host Department field indicates which team hosted the vendor.
The agent must count by Host Department and sort descending to find the top department.

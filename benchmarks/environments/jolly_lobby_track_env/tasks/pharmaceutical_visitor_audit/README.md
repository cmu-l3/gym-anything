# Pharmaceutical & Healthcare Company Visitor Audit

## Task Overview

ACME Corp's Legal and Compliance teams are conducting an industry-specific visitor audit
for pharmaceutical and healthcare companies. These visitors are subject to enhanced
documentation requirements under the company's healthcare partnership compliance program.
All visits from pharmaceutical/healthcare companies must be catalogued with full details
including visitor identity, purpose, host name, and host department.

## Your Mission

You are the Legal Compliance Analyst at ACME Corp. Search the visitor management system
for all visitors from pharmaceutical and healthcare companies in December 2025. Compile
a complete audit report and export it to the Desktop.

For this audit, the following companies are classified as pharmaceutical/healthcare:
- Johnson & Johnson
- Pfizer Inc
- Merck & Co
- UnitedHealth Group
- Abbott Laboratories

## Goal State

A file named `pharma_healthcare_visitor_audit.csv` must exist at `/home/ga/Desktop/`
containing all visitor records from the pharmaceutical/healthcare companies listed above,
with visitor name, company, purpose, host name, and host department for each visit.

## Credentials

- Application: Jolly LobbyTrack (already open)
- No username/password required

## What the Agent Must Discover

The agent must:
1. Search for each pharmaceutical/healthcare company in the visitor records
2. Identify all matching visits for December 2025
3. Collect visit details (visitor name, purpose, host, department) for each match
4. Export the combined audit report to the specified Desktop path

## Success Criteria

The file `/home/ga/Desktop/pharma_healthcare_visitor_audit.csv` must:
- Exist at the specified path
- Contain records for Johnson & Johnson, Pfizer, Merck, UnitedHealth Group, and Abbott
- Show visitor names, host departments, and visit purposes for each company

## Verification Strategy

1. File existence — prerequisite; score=0 if missing
2. Johnson & Johnson record present — 20 pts
3. Pfizer record present — 20 pts
4. Merck & Co record present — 20 pts
5. UnitedHealth Group or Abbott Laboratories present — 20 pts
6. At least 4 of the 5 companies found in report — 20 pts

Passing threshold: 60 points (3 of 5 companies)

## Schema Reference

December 2025 pharmaceutical/healthcare visitor records:
- James Smith / Johnson & Johnson / Legal / Business Meeting (Visitor)
- Patricia Williams / Pfizer Inc / Procurement / Vendor Meeting (Vendor)
- Elizabeth Moore / UnitedHealth Group / HR / Benefits Review (Visitor)
- Donald Hall / Merck & Co / Research / Clinical Trial Update (Visitor)
- Sandra Carter / Abbott Laboratories / Health & Safety / Medical Device Demo (Vendor)

# Customer Profile Enrichment

## Overview

**Difficulty**: Hard
**Occupation**: CRM Manager (B2B software company)
**Timeout**: 660 seconds | **Max steps**: 70

A multi-step CRM data quality task. The agent must navigate to customer profiles, update multiple fields, create a new customer, tag conversations belonging to a specific customer, and create a new conversation for the newly created customer. This task requires navigating 4 distinct sections of FreeScout: customer list, customer edit forms, conversation tag interface, and new conversation creation.

## Background

A B2B software company is preparing for a sales handoff meeting. The CRM data is incomplete — several enterprise customers have no company, phone, or job title on record. The CRM Manager must enrich these profiles before the meeting and ensure enterprise flagging is applied to open tickets.

## Pre-Existing State (seeded in setup_task.sh)

**Mailboxes**: Technical Support (techsupport@helpdesk.local), General Support (general@helpdesk.local)

**Customers with incomplete profiles (no company, phone, job title):**
- Marisa Obrien (carrollallison@example.com) — has 3 conversations in Technical Support
- Nicolas Wilson (joshua24@example.com) — has 2 conversations in General Support

**3 conversations for Marisa Obrien** (Technical Support):
- "Product setup" — GoPro Hero issue
- "Firmware update problem" — GoPro Hero firmware
- "Device connectivity issue" — GoPro Hero connectivity

**2 conversations for Nicolas Wilson** (General Support):
- "Installation support" — Fitbit Versa Smartwatch
- "App sync issue" — Fitbit Versa Smartwatch

## Required End State

1. Marisa Obrien profile updated: Company="Pinnacle Systems", Phone="+1-415-555-0192", Job Title="Senior Systems Engineer"
2. Nicolas Wilson profile updated: Company="Horizon Analytics", Phone="+1-212-555-0847"
3. New customer David Okafor created: email="david.okafor@techfirm.io", Company="TechFirm Solutions", Phone="+1-650-555-0312"
4. All 3 of Marisa Obrien's conversations tagged with "vip-client"
5. New conversation in Technical Support for David Okafor with specified subject and body

## Verification Criteria (100 points)

| Criterion | Points |
|-----------|--------|
| Marisa Obrien company updated to "Pinnacle Systems" | 12 |
| Marisa Obrien phone updated | 8 |
| Marisa Obrien job title updated to "Senior Systems Engineer" | 10 |
| Nicolas Wilson company updated to "Horizon Analytics" | 12 |
| Nicolas Wilson phone updated | 8 |
| David Okafor created with email and company | 15 |
| Marisa's 3 conversations tagged "vip-client" (partial credit) | 20 |
| New conversation for David Okafor created in correct mailbox | 15 |
| **Total** | **100** |

**Pass threshold**: 60 points

## Why This Is Hard

- Requires navigating to customer profiles (not conversations) — a less obvious part of the UI
- Phone and job title fields may require navigating to "Edit" mode within a customer profile
- Finding a customer's conversations and tagging them requires two context switches
- Creating a new conversation for a specific customer requires linking the customer during creation

## Data Source

Customer names and emails from the Kaggle Customer Support Ticket Dataset (chiapudding/kaggle-customer-service).

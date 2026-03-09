# Task: Set Up Department Email Routing

## Overview
A web administrator needs to set up department-based email routing for acmecorp.test. This involves creating new mail users and multiple email aliases, including a multi-destination alias that forwards to two recipients simultaneously.

## Domain Context
Email routing is a core hosting task. Businesses commonly need:
- Department mailboxes (hr@, billing@, support@)
- Vanity/role aliases (jobs@ → hr@, invoices@ → billing@)
- Multi-destination aliases for shared inboxes (contact@ → info@ AND admin@)

## Goal
Create 2 new mail users and 3 email aliases (one with multiple destinations) for acmecorp.test.

## Why This Is Hard
- The agent must use two distinct Virtualmin features: user creation and alias creation
- Multi-destination aliases require finding the correct UI to add multiple recipients
- The agent must navigate between different sections of the acmecorp.test domain
- 5 independent subtasks that can be partially completed

## Verification Strategy
- Check each user exists via `virtualmin list-users`
- Check each alias exists and forwards to correct destination(s) via `virtualmin list-aliases`
- The multi-destination alias (contact@) must forward to BOTH recipients

## Edge Cases and Potential Issues
- Agent may confuse "mail forwarding" (redirecting all mail for a user) with "aliases" (additional addresses)
- Multi-destination aliases (contact@) require finding the correct UI or CLI syntax to add two recipients
- `info@` and `admin@` already exist as Virtualmin system users — the alias must forward to these existing addresses
- `virtualmin list-users --name-only` outputs `user@domain` format (e.g., `hr@acmecorp.test`), not just `hr`
- `virtualmin list-aliases` outputs tabular format with space-separated columns, not `from dest` pairs
- Agent might create users under the wrong domain if it doesn't select acmecorp.test first
- Some aliases may require the full email address as destination, others just the local part

## Ground Truth
- Users: hr, billing (under acmecorp.test)
- Aliases: jobs→hr, invoices→billing, contact→{info,admin}

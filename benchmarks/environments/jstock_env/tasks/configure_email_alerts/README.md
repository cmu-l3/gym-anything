# Configure Email Notification Settings for Stock Alerts (`configure_email_alerts@1`)

## Overview

This task evaluates the agent's ability to configure JStock's email notification system for stock price alerts. The agent must navigate to JStock's Options dialog, locate the email/alert configuration tab, and enter specific SMTP settings so that price threshold alerts can be delivered via email. This tests interaction with a multi-tabbed preferences dialog and correct data entry for a communication configuration workflow.

## Rationale

**Why this task is valuable:**
- Tests navigation of a multi-tabbed application preferences dialog
- Requires precise data entry in configuration fields (server, port, credentials)
- Evaluates understanding of email/SMTP infrastructure concepts within a finance application
- Verifiable through JStock's persistent configuration files on disk

**Real-world Context:** A busy portfolio manager who tracks 50+ stocks across multiple watchlists has set Fall Below / Rise Above price alert thresholds on key positions. They need to configure email notifications so JStock automatically sends an alert email when a stock price crosses a threshold.

## Task Description

**Goal:** Configure JStock's email alert notification settings with specific SMTP server details.

**Starting State:** JStock is open on the main watchlist view. No email alert settings have been previously configured.

**Expected Actions:**
1. Open JStock's Options/Preferences dialog (accessible via the Edit or Options menu).
2. Navigate to the "Email" or "Alert" tab within the Options dialog.
3. Enable email notifications (check the enable checkbox if present).
4. Configure the following SMTP settings:
   - **SMTP Server:** `smtp.gmail.com`
   - **SMTP Port:** `587`
   - **Email Username/Authentication:** `portfolio.alerts@gmail.com`
   - **Email Password:** `JStock2024Alert!`
5. Click OK/Apply to save the settings.

**Final State:**
- JStock's email alert settings are saved.
- The Options dialog is closed.

## Verification Strategy

### Primary Verification: Configuration File Inspection
The verifier searches JStock's configuration files (typically `~/.jstock/`) for the entered SMTP settings. It checks that the specific strings (`smtp.gmail.com`, `portfolio.alerts@gmail.com`) are present in files modified after the task started.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| SMTP Server Configured | 30 | `smtp.gmail.com` found in config |
| Email Address Configured | 30 | `portfolio.alerts@gmail.com` found in config |
| Port Configured | 20 | `587` found in config |
| File Modified Correctly | 20 | Config file timestamp > task start time |
| **Total** | **100** | |

Pass Threshold: 60 points (Must have at least Server and Email correct).
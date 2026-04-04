# Configure FTP Access Users for a Virtual Server (`create_ftp_users@1`)

## Overview
This task requires the agent to create FTP-only user accounts within an existing virtual server, granting external collaborators the ability to upload website files while strictly limiting their access—no email, no shell, no control panel login.

## Rationale
**Why this task is valuable:**
- Tests navigation of Virtualmin's user management interface
- Requires understanding feature toggles (FTP yes, email no, shell no)
- Involves setting specific custom home directories
- Validates the agent can create restricted access profiles

**Real-world Context:** A hosting administrator needs to provide freelance developers with FTP access to specific directories without giving them email accounts or shell access.

## Task Description

**Goal:** Create two FTP-only user accounts for the `acmecorp.test` virtual server with specific credentials and directory restrictions.

**Starting State:** Firefox is open and logged into Virtualmin. The `acmecorp.test` virtual server exists.

**Detailed Requirements:**

1. **User 1 — alice_dev:**
   - Username: `alice_dev`
   - Real name: `Alice Chen`
   - Password: `DevAccess2024!`
   - FTP access: **Enabled**
   - Email: **Disabled**
   - Home directory: `/home/acmecorp/public_html`
   - Shell: `/bin/false` (or /usr/sbin/nologin)

2. **User 2 — dave_uploads:**
   - Username: `dave_uploads`
   - Real name: `Dave Martinez`
   - Password: `UploaderPass99!`
   - FTP access: **Enabled**
   - Email: **Disabled**
   - Home directory: `/home/acmecorp/public_html/uploads` (create directory if it doesn't exist)
   - Shell: `/bin/false` (or /usr/sbin/nologin)

**Final State:** Both users exist with the specified configurations.

## Verification Strategy
The verifier checks the system state using `virtualmin list-users` and system password files to ensure:
1. Users exist
2. FTP is enabled and Email is disabled
3. Home directories match requirements
4. Shell is set to a non-interactive shell
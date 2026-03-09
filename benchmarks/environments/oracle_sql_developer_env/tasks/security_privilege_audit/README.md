# Task: Security Privilege Audit and Remediation

## Overview

A recently completed Oracle database security review has flagged five user accounts in the XEPDB1 database as having dangerously excessive privileges. You are a Compliance Officer / Database Security Analyst. Your job is to audit and remediate all five accounts, then configure Oracle Unified Auditing policies to detect future privilege escalation attempts.

The five accounts were created by a previous DBA who violated least-privilege principles. Each has a distinct misconfiguration that must be individually diagnosed and corrected.

## Context

Oracle database privilege management is a core compliance task for organizations subject to SOX, PCI-DSS, or internal security standards. Compliance Officers routinely audit user accounts to identify over-privileged users, revoke excessive grants, and implement audit trails. This task requires understanding Oracle's role hierarchy, system privileges, and unified auditing framework.

## Goal

1. **Audit all five misconfigured accounts** — examine each user's roles, system privileges, and object privileges to understand what they have and why it is excessive.

2. **Remediate each account** to follow least-privilege principles:
   - `DEV_USER`: Should only have CREATE SESSION and CREATE TABLE in their own schema
   - `REPORT_USER2`: Should only have CREATE SESSION and SELECT on specific HR tables (employees, departments, jobs)
   - `ANALYST_USER`: Should only have CREATE SESSION and CREATE VIEW
   - `APP_USER`: Should only have CREATE SESSION (application uses stored procedures only)
   - `LEGACY_USER`: Account should be LOCKED (retired system account, must not be dropped — just locked)

3. **Create and enable an Oracle Unified Audit policy** named `PRIVILEGE_ESCALATION_AUDIT` that audits the following actions: GRANT ANY PRIVILEGE, CREATE USER, DROP USER, ALTER USER, CREATE ROLE.

4. **Export a security remediation report** to `/home/ga/Documents/exports/security_remediation.txt` documenting what privileges were found and what was done for each account.

## Login Credentials

- **Oracle SQL Developer**: Use the pre-configured "HR Database" connection (hr/hr123) or connect as SYSTEM (system/OraclePassword123)
- **Database**: XEPDB1 on localhost:1521

## Success Criteria

- All five user accounts have their excessive privileges revoked
- `LEGACY_USER` is locked
- `PRIVILEGE_ESCALATION_AUDIT` policy exists and is enabled
- Security remediation report file exists with meaningful content

## Verification Strategy

1. **DEV_USER remediated** (20 pts): DBA role revoked; no system privileges beyond CREATE SESSION and CREATE TABLE
2. **REPORT_USER2 remediated** (15 pts): CREATE TABLE and SELECT ANY TABLE revoked; only has CREATE SESSION + object-level grants
3. **APP_USER remediated** (15 pts): RESOURCE role and UNLIMITED TABLESPACE revoked
4. **LEGACY_USER locked** (10 pts): Account status = LOCKED
5. **Audit policy configured** (15 pts): PRIVILEGE_ESCALATION_AUDIT policy exists and is enabled
6. **GUI usage** (25 pts): Evidence that Oracle SQL Developer GUI was used

Pass threshold: 60 pts

## Technical Notes

- Connect as SYSTEM to manage users and audit policies
- Oracle Unified Auditing: `CREATE AUDIT POLICY ... PRIVILEGES ...` then `AUDIT POLICY ...`
- Check current privileges: `SELECT * FROM dba_sys_privs WHERE grantee = 'DEV_USER'`
- Check roles: `SELECT * FROM dba_role_privs WHERE grantee = 'DEV_USER'`
- Revoke role: `REVOKE DBA FROM DEV_USER`
- Lock account: `ALTER USER LEGACY_USER ACCOUNT LOCK`
- Audit policy: `CREATE AUDIT POLICY priv_audit PRIVILEGES GRANT ANY PRIVILEGE, CREATE USER, DROP USER, ALTER USER, CREATE ROLE; AUDIT POLICY priv_audit;`

## Schema Reference

Relevant Oracle catalog views:
- `dba_sys_privs`: System privileges by grantee
- `dba_role_privs`: Roles granted to users
- `dba_users`: User account status (OPEN/LOCKED/EXPIRED)
- `audit_unified_policies`: Unified audit policy definitions
- `audit_unified_enabled_policies`: Currently enabled policies

# Multi-Tenant Data Isolation

## Domain Context

Software developers building multi-tenant SaaS platforms must implement robust data isolation to prevent tenants from accessing each other's data. Oracle's Virtual Private Database (VPD) feature, implemented through DBMS_RLS, provides row-level security that transparently filters queries based on the authenticated tenant. Security audits frequently reveal misconfigurations in VPD policies that create data leakage vulnerabilities. This task reflects real-world security engineering work performed by senior developers on enterprise SaaS platforms.

**Occupation**: Software Developers (SOC 15-1252)
**Industry**: Technology / SaaS
**GDP Contribution**: $4.5B annually

## Task Overview

The SAAS_PLATFORM schema implements a multi-tenant architecture with VPD policies. A security audit has revealed three critical data isolation failures:

1. **Broken Policy Function**: The TENANT_ISOLATION_POLICY function on CUSTOMER_DATA returns NULL (no filtering) instead of '1=0' (deny all) when the application context is not set or is set to superuser (tenant_id=0). This means unauthenticated queries see ALL tenant data.
2. **Missing Policy**: The FINANCIAL_RECORDS table has no VPD policy at all, exposing all tenant financial data to any authenticated user regardless of their tenant.
3. **Context Default Bug**: The TENANT_CTX_PKG package defaults to tenant_id=0 (superuser) when no tenant ID is provided, instead of defaulting to tenant_id=-1 (no access).

Tasks:
- Diagnose all three security flaws
- Fix the policy function to return '1=0' for null/superuser contexts
- Add VPD policy to FINANCIAL_RECORDS using DBMS_RLS.ADD_POLICY
- Fix context package to default to -1 instead of 0
- Create SECURITY_AUDIT_LOG table, CROSS_TENANT_VIOLATION_VW view, and PROC_SECURITY_AUDIT_REPORT procedure
- Verify isolation works for all three tenants

## Credentials

- Admin schema: `saas_admin` / `SaaS2024`
- Tenant 1: `tenant1_user` / `Tenant1Pass`
- Tenant 2: `tenant2_user` / `Tenant2Pass`
- Tenant 3: `tenant3_user` / `Tenant3Pass`
- System: `system` / `OraclePassword123`

## Success Criteria

- TENANT_ISOLATION_POLICY function returns '1=0' for null/zero tenant contexts
- FINANCIAL_RECORDS table has a VPD policy via DBMS_RLS
- TENANT_CTX_PKG defaults to tenant_id=-1 (not 0)
- All three tenants can only see their own data in CUSTOMER_DATA
- Tenant 1 can only see their own financial records
- SECURITY_AUDIT_LOG table, CROSS_TENANT_VIOLATION_VW view, and PROC_SECURITY_AUDIT_REPORT procedure exist
- SQL Developer GUI was used

## Verification Strategy

- **Policy function**: ALL_SOURCE text checked for '1=0' return and absence of 'RETURN NULL'
- **Financial policy**: ALL_POLICIES checked for policy on FINANCIAL_RECORDS
- **Context package**: ALL_SOURCE checked for '-1' default and absence of '0' default
- **Tenant isolation**: Cross-tenant queries tested via tenant user connections
- **Audit infrastructure**: ALL_TABLES, ALL_VIEWS, ALL_PROCEDURES checked
- **GUI**: SQL history, MRU cache, active sessions

## Schema Reference

```sql
SAAS_ADMIN.TENANTS (tenant_id, tenant_name, subdomain, plan_tier, created_date, is_active)
SAAS_ADMIN.CUSTOMER_DATA (record_id, tenant_id, customer_name, email, phone, address, created_date) -- HAS VPD policy (broken)
SAAS_ADMIN.FINANCIAL_RECORDS (record_id, tenant_id, transaction_type, amount, currency, description, transaction_date, invoice_number) -- MISSING VPD policy
SAAS_ADMIN.API_KEYS (key_id, tenant_id, api_key, key_name, permissions, created_date, is_active)
SAAS_ADMIN.USER_SESSIONS (session_id, tenant_id, user_email, login_time, logout_time, ip_address)
SAAS_ADMIN.SECURITY_AUDIT_LOG (log_id, event_type, tenant_id, table_name, policy_result, event_timestamp, session_user)
```

## Difficulty: very_hard

The agent must independently:
- Understand Oracle VPD/DBMS_RLS architecture
- Read and debug PL/SQL policy function code to find the logic error
- Understand application context mechanisms (DBMS_SESSION, SYS_CONTEXT)
- Know that NULL return from a policy function means "no restriction" in Oracle VPD
- Write DBMS_RLS.ADD_POLICY calls with correct parameters
- Design security audit procedures that test cross-tenant access

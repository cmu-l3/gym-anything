# Task: multi_user_energy_monitoring_setup

## Overview

An IT operations engineer must onboard two commercial tenants onto a shared Emoncms
energy monitoring server. Each tenant needs their own isolated user account with
separate API keys, inputs, feeds, and dashboards. The engineer must create both
accounts, post initial data using each tenant's credentials, configure the logging
pipeline, and build dedicated dashboards.

## Domain Context

Facilities managers and IT engineers who manage multi-tenant buildings use Emoncms
multi-user features so that:
- Each tenant can only access their own energy data
- Data is posted using per-user API keys (not the shared admin key)
- Each tenant has their own dashboard tailored to their floor/unit

## Goal

1. **Create user accounts**:
   - Username: `tenant_a`, email: `tenant_a@building.local`
   - Username: `tenant_b`, email: `tenant_b@building.local`

2. **Post data using each tenant's own API key**:
   - Use `tenant_a`'s write API key to post: `floor_a` node, inputs `hvac_w` and `lighting_w`
   - Use `tenant_b`'s write API key to post: `floor_b` node, inputs `hvac_w` and `lighting_w`

3. **Configure input process lists** for each tenant's inputs:
   - Each input must log to a named feed owned by that tenant (not admin)

4. **Create dashboards**:
   - Dashboard named `'Tenant A Energy'` owned by `tenant_a`
   - Dashboard named `'Tenant B Energy'` owned by `tenant_b`

## Success Criteria

| Criterion | Points |
|-----------|--------|
| User `tenant_a` exists | 10 |
| `tenant_a` has ≥ 2 inputs with non-empty process lists | 25 |
| `tenant_a` has ≥ 2 feeds | 15 |
| User `tenant_b` exists | 10 |
| `tenant_b` has ≥ 2 inputs with non-empty process lists | 25 |
| `tenant_b` has ≥ 2 feeds | 15 |
| **Total** | **100** |
| **Pass threshold** | **≥ 60** |

Note: Dashboard creation is not scored programmatically because dashboard APIs do
not reliably expose per-user owner info without admin auth. The inputs+feeds
criteria are the primary verification mechanism.

## How to Get a User's API Key

After creating the user via the Emoncms web UI, retrieve their API key via:
```
http://localhost/user/view.json?apikey=ADMIN_WRITE_KEY
```
Or navigate to their account settings in the UI.

Alternatively, query the database:
```sql
SELECT apikey_write FROM users WHERE username='tenant_a';
```

## Post Data Using a Specific API Key

```bash
curl "http://localhost/input/post?apikey=TENANT_A_WRITE_KEY&node=floor_a&fulljson=%7B%22hvac_w%22%3A2400%2C%22lighting_w%22%3A600%7D"
```

## Credentials (Admin)

- URL: http://localhost
- Username: admin
- Password: admin

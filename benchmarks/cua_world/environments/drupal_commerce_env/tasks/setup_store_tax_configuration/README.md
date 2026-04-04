# setup_store_tax_configuration

## Domain Context

Online merchants must configure their store for tax compliance — setting the correct timezone, registering tax jurisdictions, maintaining accurate business addresses, and assigning staff roles. This task touches store settings, the tax module, user management, and address configuration.

## Goal

Complete a multi-part store configuration for tax compliance at Urban Electronics:

1. Update store timezone to America/Los_Angeles (Pacific Time)
2. Add US to the store's tax registration countries
3. Change the store address to "100 Commerce Boulevard"
4. Create a `taxmanager` user account with email `tax@urbanelectronics.com`
5. Ensure the commerce_tax module is enabled and the default currency is USD

## Success Criteria

| # | Criterion | Points | Description |
|---|-----------|--------|-------------|
| 1 | Timezone = America/Los_Angeles | 20 | Store timezone updated from UTC |
| 2 | US tax registration | 20 | US present in commerce_store_tax_registrations |
| 3 | Address = 100 Commerce Boulevard | 20 | Store address_line1 updated |
| 4 | taxmanager user created | 20 | User with correct username and email exists |
| 5 | commerce_tax enabled + USD currency | 20 | Module active (10pts) + currency is USD (10pts) |

**Pass threshold:** 60/100 (3 of 5 subtasks)

## Verification Strategy

- **Baseline recording:** Initial timezone, address, tax registration count, and user count saved
- **Gate:** If no changes detected (timezone, address, user, tax registrations all unchanged), score = 0
- **Independent criteria:** Each configuration item is scored independently

## Schema Reference

| Table | Key Fields |
|-------|-----------|
| `commerce_store_field_data` | store_id, timezone, default_currency, address__address_line1 |
| `commerce_store__tax_registrations` | entity_id (store_id), tax_registrations_value (country code) |
| `users_field_data` | uid, name, mail |

## Edge Cases

- Agent might set wrong timezone format — exact match required
- Agent might add tax registration for wrong country — checks for "US" specifically
- taxmanager user might be created with wrong email — partial credit (10/20)
- commerce_tax module might already be enabled — still gets points if currency is correct
- Existing taxmanager user is cleaned up in setup to prevent false positives

# Odoo Inventory Environment - Evidence Documentation

This folder contains evidence of environment setup and testing.

## Environment Overview

- **Application**: Odoo 17 Community Edition
- **Module**: Inventory (stock)
- **Database**: PostgreSQL 15 (via Docker)
- **Browser**: Firefox
- **VM Resolution**: 1920x1080

## Verification Checklist

| Check | Status | Evidence |
|-------|--------|----------|
| Installation script completes | ✅ PASS | `pre_start_log.txt` - Docker installed |
| Setup script completes | ✅ PASS | `post_start_log.txt` - containers started |
| Docker containers running | ✅ PASS | `docker_status.txt` - both healthy |
| Firefox opens correctly | ✅ PASS | `04_setup_complete.png` |
| Export script runs | ⚠️ REQUIRES DB | Only works after database created |
| Verifier can process result | ⚠️ REQUIRES DB | Only works after database created |

## Initial State

**IMPORTANT**: On first run, the environment shows the **database creation page**, NOT the login page.

The agent will see one of:
1. Database creation form (if no database exists)
2. Odoo login page (if database was cached or created)

**Screenshot Evidence**:
- `04_setup_complete.png` shows database creation form
- `test_screenshot.png` shows database creation form

## Test Results

### Environment Setup
- Docker containers (odoo-web, odoo-postgres) start successfully and are healthy
- Firefox launches and navigates to Odoo at `http://localhost:8069`
- Database creation is automated via Odoo CLI during setup (or done through UI)

### Docker Container Status
```
CONTAINER ID   IMAGE         STATUS                    NAMES
2eecbe9ac28b   odoo:17.0     Up (healthy)              odoo-web
14e4e9547ec4   postgres:15   Up (healthy)              odoo-postgres
```

### Task: Create Product

**Test Product Details (from earlier manual test):**
- Name: Industrial Safety Helmet
- Internal Reference: HELM-IND-001
- Barcode: 5901234123457
- Product Type: Storable Product

**Note**: Previous test had incorrect Sales Price ($1.00 instead of $45.00) and Cost ($0.00 instead of $28.00). Task description now emphasizes EXACT values required.

## Screenshots

1. `04_setup_complete.png` - Database creation form (initial state on fresh start)
2. `test_screenshot.png` - Fresh start showing database creation page

Note: Screenshots 01-03 were removed as they showed a logged-in state that doesn't match
the actual initial state of the environment (which shows the database creation page).

## Setup Logs

### Pre-Start Log (`pre_start_log.txt`)
- Package updates (apt-get update)
- Docker installation (docker.io, docker-compose)
- Service enablement

### Post-Start Log (`post_start_log.txt`)
- Docker Compose configuration
- Image pulls (odoo:17.0, postgres:15)
- Container startup
- Firefox profile configuration

## Technical Notes

### Odoo 17 Schema Changes
- Translatable fields stored as JSONB: `{"en_US": "value"}`
- Query with: `name->>'en_US'` to extract English text
- Barcode is in `product_product` table, not `product_template`
- Cost (standard_price) is in `ir_property` table or `product_product`

### Database Creation
The setup script attempts to create the database via Odoo CLI. If this fails, the agent will see the database creation form.

Database creation fields:
- Database Name: `odoo_inventory`
- Email: `admin`
- Password: `admin`
- Check "Demo Data" checkbox

### Verification Changes (Post-Audit)

The following improvements were made:

1. **Exact matching**: Verifiers now require EXACT match for product names, references, and barcodes (no substring matching)
2. **Cost extraction**: Export script now properly extracts cost from Odoo 17's ir_property table
3. **Reason verification**: adjust_inventory now requires "Annual Stock Count" in the reason field
4. **No partial credit for wrong product**: Adjusting the wrong product gives 0 points
5. **Task descriptions updated**: Initial state (database creation) is now documented

### Login Credentials
- Email/Username: `admin`
- Password: `admin`

## Known Limitations

1. Database creation cannot be fully automated due to CSRF protection
2. Cost field extraction depends on Odoo version's storage method
3. First run requires database creation through UI or CLI

## Date
Last updated: 2026-02-03

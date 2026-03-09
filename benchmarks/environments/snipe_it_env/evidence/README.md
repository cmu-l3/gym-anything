# Snipe-IT Environment - Evidence Documentation

## Test Details
- **Date**: 2026-02-15
- **Test type**: Fresh boot (no cache), `use_cache=False`
- **Task tested**: `create_asset`
- **Base image**: `ubuntu-gnome-systemd_highres`
- **Resources**: 8GB RAM, 4 CPUs, networking enabled

## Screenshots

| # | File | Description |
|---|------|-------------|
| 1 | `01_login_page.png` | Firefox open to Snipe-IT login page at `http://localhost:8000/login` |
| 2 | `02_dashboard.png` | Dashboard after successful login showing 19 assets, 160 license seats, 3 accessories, 1 consumable, 2 components, 11 people |
| 3 | `03_hardware_list_page1.png` | Hardware asset list (first 9 of 19) - Cisco switches, Dell Latitude, Dell Latitude 7440, OptiPlex, PowerEdge |
| 4 | `04_hardware_list_page2.png` | Hardware asset list (remaining 10) - Dell monitors, HP EliteBook, EliteDesk, Lenovo ThinkPad, MacBook Pro, Samsung Odyssey. Pagination: "Showing 1 to 19 of 19 rows" |
| 5 | `05_create_asset_task_start.png` | Dashboard view - the starting state for `create_asset` task. "Create New" button visible in top nav. |
| 6 | `06_checkout_asset_l002_ready.png` | ASSET-L002 (Dell Latitude 5540 - Finance Pool) showing "Ready to Deploy" status with pink "Checkout" button visible |
| 7 | `07_users_list.png` | All 11 users listed with names, job titles, departments. Michael Thompson (mthompson) visible as checkout target. |

## Log Evidence

| File | Description |
|------|-------------|
| `pre_start_log.txt` | Installation hook output - Docker, Docker Compose v2, Firefox, GUI tools |
| `post_start_log.txt` | Setup hook output - Docker containers, DB migrations, admin user, OAuth keys, API token, data seeding |
| `pre_task_log_create_asset.txt` | Task setup for `create_asset` - initial asset count: 20, max ID: 20 |
| `docker_status.txt` | Docker container status showing `snipeit-app` and `snipeit-db` both running |
| `api_verification.txt` | API endpoint counts: 19 hardware, 11 users, 16 categories, 11 models, 7 status labels, 8 manufacturers, 6 locations, 7 departments, 3 suppliers, 3 accessories, 1 consumable, 2 components |

## Verification Checklist

- [x] Installation script completes without errors (pre_start hook)
- [x] Setup script completes without errors (post_start hook)
- [x] Docker containers running (snipeit-app + snipeit-db)
- [x] Snipe-IT accessible at http://localhost:8000
- [x] Admin login works (admin / password)
- [x] API token generated and functional
- [x] Firefox opens and displays Snipe-IT login page
- [x] Dashboard shows correct data counts
- [x] 19 hardware assets visible (20 total, 1 archived/retired)
- [x] 11 users (10 employees + admin)
- [x] Asset checkouts visible (Sarah Chen, James Rodriguez, Emily Watson, David Kim, Anna Kowalski)
- [x] Task setup (pre_task) runs successfully
- [x] create_asset task start state: Dashboard with "Create New" button accessible
- [x] checkout_asset task: ASSET-L002 in "Ready to Deploy" status with Checkout button

## Data Summary

### Hardware Assets (20 total, 19 visible)
- 5 Laptops checked out to users
- 4 Laptops available (Ready to Deploy, Out for Repair)
- 3 Desktops (Deployed)
- 3 Monitors (2 Deployed, 1 Ready to Deploy)
- 2 Networking switches (Deployed)
- 2 Servers (Deployed)
- 1 Retired laptop (archived, not shown in default view)

### Users (11 total)
10 employees across 7 departments (IT, Engineering, HR, Finance, Marketing, Sales, Operations) + 1 admin

### Other Entities
- 16 categories (asset, license, accessory, consumable, component types)
- 8 manufacturers (Dell, HP, Lenovo, Apple, Cisco, Samsung, Microsoft, Logitech)
- 6 locations (HQ A/B, NYC, Austin, London, Remote)
- 7 departments
- 3 suppliers (CDW, Insight Direct, SHI International)
- 3 licenses (M365, Adobe CC, Windows 11)
- 3 accessories (mouse, adapter, headset)
- 1 consumable (toner)
- 2 components (RAM, SSD)

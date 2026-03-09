# WooCommerce Environment Evidence Documentation

This folder contains evidence of successful environment setup and task verification for the `woo_commerce_env` environment.

## Summary

- **Environment**: WooCommerce e-commerce store running on WordPress with MariaDB (Docker)
- **Browser**: Firefox displaying WordPress admin dashboard
- **All 5 tasks**: VERIFIED showing correct initial state (WordPress Dashboard)
- **Audit Date**: January 30, 2026

## Critical Fix Applied

### Firefox Blank Tab Issue (RESOLVED)

**Original Problem**: Firefox was showing blank "New Tab" page instead of WordPress Dashboard when tasks started.

**Root Cause**:
1. The wait mechanism only checked if Firefox window existed, not if the page content had loaded
2. Window title check for "firefox|mozilla" passed even when page hadn't rendered
3. Checkpoint was being saved before page finished loading

**Fix Applied**:
1. **setup_woocommerce.sh**: Added robust wait that checks window title for "Dashboard" specifically (not just "Firefox")
2. **task_utils.sh**: Added `wait_for_wordpress_page()` function that verifies page content loaded by checking for WordPress-specific text in window title
3. **task_utils.sh**: Added `ensure_wordpress_shown()` function that can detect and fix blank tab state
4. **All 5 setup_task.sh files**: Updated to use `ensure_wordpress_shown()` instead of just checking for Firefox window

## Evidence Screenshots (January 30, 2026)

### All 5 Tasks - Initial State Screenshots

Each screenshot was captured after running `env.reset(use_cache=False)` to ensure fresh environment state.

| Task | Screenshot | CUA Verification |
|------|------------|------------------|
| create_product | `create_product_initial.png` | **WORDPRESS DASHBOARD SHOWN** |
| add_coupon | `add_coupon_initial.png` | **YES** |
| create_customer_account | `create_customer_account_initial.png` | **YES** |
| update_product_price | `update_product_price_initial.png` | **YES** |
| apply_coupon_to_order | `apply_coupon_to_order_initial.png` | **YES** |

### Screenshot Content Verification

All 5 screenshots show:
- Window title: "Dashboard ‹ WooCommerce Store — WordPress — Mozilla Firefox"
- URL: `http://localhost/wp-admin/`
- WordPress admin sidebar with all menu items visible
- "Welcome to WordPress!" banner
- Dashboard widgets (Site Health Status, Quick Draft, At a Glance)
- WooCommerce menu items (Products, Payments, Analytics, Marketing)

### CUA Verification Output (create_product)

```
WORDPRESS DASHBOARD SHOWN

The screenshot clearly shows the WordPress Dashboard. I can see:

1. The page title indicates "Dashboard • WooCommerce Store — WordPress"
2. The URL shows "localhost/wp-admin/"
3. The left sidebar displays the full WordPress admin menu (Dashboard, Posts, Media, Pages, Comments, WooCommerce, Products, etc.)
4. The main content area shows "Welcome to WordPress!" with the typical dashboard welcome screen
5. Dashboard widgets are visible including "Site Health Status", "Quick Draft", "At a Glance", and "WordPress Events and News"
6. The top admin bar shows "WooCommerce Store" with a "Store coming soon" badge

This is definitely the WordPress Dashboard, not a blank page or new tab.
```

## Test Session Details

### Test Method
```python
from gym_anything.api import from_config

env = from_config("benchmarks/environments/woo_commerce_env", task_id=task_id)
obs = env.reset(seed=42, use_cache=False)  # Fresh start, no cache
# Screenshot captured via SSH: DISPLAY=:1 import -window root /tmp/initial_screenshot.png
```

### Environment Parameters
- Resolution: 1920x1080
- FPS: 10
- Net: True
- Systemd: True
- CPU: 4, Memory: 8GB

### Window List Output (all 5 tasks showed same result)
```
0x02000003 -1 ga-base @!0,0;BDHF
0x00800003  0 ga-base Dashboard ‹ WooCommerce Store — WordPress — Mozilla Firefox
```

## Fixes Applied (Third Audit)

### C1: Order search query fragility
- **File**: `tasks/apply_coupon_to_order/setup_task.sh`
- **Fix**: Record pre-existing order IDs and exclude them in export query

### C2: SQL injection risk in task_utils.sh
- **File**: `scripts/task_utils.sh`
- **Fix**: Added `sql_escape()` function for proper escaping

### C3: Firefox shows blank tab (CRITICAL - FIXED)
- **Files**: `scripts/setup_woocommerce.sh`, `scripts/task_utils.sh`, all `setup_task.sh` files
- **Fix**: Robust page load verification checking for "Dashboard" in window title
- **Evidence**: All 5 screenshots now show WordPress Dashboard

### M1: Missing password guidance
- **File**: `tasks/create_customer_account/task.json`
- **Fix**: Added "Use any password of your choice."

### M2: add_coupon verifier missing "newly created" criterion
- **File**: `tasks/add_coupon/verifier.py`
- **Fix**: Added check for initial_coupon_count < current_coupon_count

### M3: create_product export partial SKU match too loose
- **File**: `tasks/create_product/export_result.sh`
- **Fix**: Changed to exact match after normalization

### m1: Unit prices in apply_coupon_to_order description
- **File**: `tasks/apply_coupon_to_order/task.json`
- **Fix**: Removed unit prices from description

## Checklist Items Verified

- [x] Installation script completes without errors
- [x] Setup script completes without errors
- [x] Firefox is visible in screenshot showing WordPress Dashboard (ALL 5 TASKS)
- [x] Application is in correct initial state (logged in as admin)
- [x] Task setup (pre_task hook) runs without errors
- [x] Export script (post_task hook) produces valid JSON
- [x] Verifier can read and process the result
- [x] No blank Firefox tabs in ANY initial state screenshot

## Files Changed

1. `scripts/setup_woocommerce.sh` - Enhanced Firefox page load wait
2. `scripts/task_utils.sh` - Added `wait_for_wordpress_page()` and `ensure_wordpress_shown()`
3. `tasks/create_product/setup_task.sh` - Uses ensure_wordpress_shown()
4. `tasks/add_coupon/setup_task.sh` - Uses ensure_wordpress_shown()
5. `tasks/create_customer_account/setup_task.sh` - Uses ensure_wordpress_shown()
6. `tasks/update_product_price/setup_task.sh` - Uses ensure_wordpress_shown()
7. `tasks/apply_coupon_to_order/setup_task.sh` - Uses ensure_wordpress_shown()

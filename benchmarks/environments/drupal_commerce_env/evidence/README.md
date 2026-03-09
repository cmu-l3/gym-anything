# Drupal Commerce Environment - Verification Evidence

This directory contains screenshots and documentation from interactive testing of the Drupal Commerce environment (Phase 6 and Phase 7 of the environment creation workflow).

## Environment Details

| Property | Value |
|----------|-------|
| Environment ID | `drupal_commerce_env@0.1` |
| Base Image | `ubuntu-gnome-systemd_highres` |
| RAM | 8 GB |
| Drupal Version | 10.x (via `drupal/recommended-project`) |
| Commerce Version | 3.x (`drupal/commerce`) |
| Database | MariaDB 10.6 (Docker container `drupal-mariadb`) |
| PHP | 8.3 with required extensions |
| Web Server | Apache 2 |
| CLI Tools | Drush, Composer |
| Admin Login | `admin` / `Admin1234!` (via Drush ULI one-time login) |

## Verification Checklist

### Installation (pre_start hook: `install_drupal_commerce.sh`)

- [x] Docker and Docker Compose installed
- [x] Apache 2 + PHP 8.3 with all required extensions installed
- [x] Composer installed globally
- [x] Drupal core downloaded via `composer create-project drupal/recommended-project`
- [x] Composer `minimum-stability` set to `RC` (required for `drupal/inline_entity_form` dependency)
- [x] `drupal/commerce` installed via `composer require drupal/commerce -W`
- [x] `drush/drush` installed
- [x] `drupal/admin_toolbar` installed
- [x] Apache configured with DocumentRoot at `/var/www/html/drupal/web`
- [x] Firefox, wmctrl, xdotool installed for GUI automation

### Setup (post_start hook: `setup_drupal_commerce.sh`)

- [x] MariaDB container started via Docker Compose
- [x] Drupal site installed via `drush site:install standard`
- [x] Commerce modules enabled: commerce, commerce_product, commerce_order, commerce_cart, commerce_checkout, commerce_payment, commerce_promotion, commerce_tax, commerce_store, commerce_price, commerce_log
- [x] Admin Toolbar enabled for better admin UX
- [x] Administrator role granted all Commerce permissions
- [x] Admin user assigned administrator role
- [x] 12 products seeded via `seed_products.php`
- [x] 3 promotions seeded via `seed_promotions.php` (2 with coupons: WELCOME10, SAVE25)
- [x] 3 customer accounts created (johndoe, janesmith, mikewilson)
- [x] Firefox launched with Drush ULI one-time login, redirected to Commerce admin
- [x] Firefox profile configured (no first-run screens, homepage set to Commerce admin)

### Application State Verified via Screenshots and visual_grounding MCP Tool

- [x] Commerce admin dashboard visible (see `commerce_admin_dashboard.png`)
- [x] Products page showing seeded products (see `products_page.png`)
- [x] Promotions page showing all 3 promotions (see `promotions_page.png`)

### Task Start States Verified via visual_grounding MCP Tool

- [x] create_product: Products admin page with "+ Add product" button visible (see `create_product_task_start_state.png`)
- [x] create_coupon: Promotions admin page with "+ Add promotion" button visible (see `create_coupon_task_start_state.png`)
- [x] add_to_cart: Product catalog page at `/products` showing product listing (see `add_to_cart_task_start_state.png`)

### Task Completability Verified Interactively

- [x] create_product: Successfully created "Organic Bamboo Wireless Charger" (SKU: OBW-CHR-01, $39.99) via GUI interaction (see `create_product_task_completed.png`, `create_product_variation_form.png`)
- [x] create_coupon: Successfully created "Summer Sale 20% Off" promotion with coupon code SUMMER20 (see `create_coupon_task_completed.png`)
- [x] add_to_cart: Successfully added Sony WH-1000XM5 to cart with confirmation banner (see `add_to_cart_task_completed.png`)

## Evidence Screenshots

### 1. `commerce_admin_dashboard.png`

**What it shows:** The Drupal Commerce administration dashboard at `http://localhost/admin/commerce`.

**Key observations:**
- Page title: "Commerce | Drupal Commerce Store - Mozilla Firefox"
- URL bar shows `http://localhost/admin/commerce`
- Admin toolbar visible at top with Commerce, Content, Structure, Appearance, etc.
- Four main sections visible: Orders, Products, Promotions, Configuration
- Inbox area shows "Welcome to Drupal Commerce!" message
- Statistics widgets: New carts, Placed orders, Gross sales, Average order
- Best selling products and Most used promotions sections visible (empty since no orders placed yet)
- Admin logged in as "admin" (visible in toolbar)

### 2. `products_page.png`

**What it shows:** The Commerce Products listing page at `http://localhost/admin/commerce/products`.

**Key observations:**
- Page title: "Products | Drupal Commerce Store - Mozilla Firefox"
- URL: `http://localhost/admin/commerce/products`
- "+ Add product" button visible at top
- Title filter and "Filter" button visible
- Product list columns: Title, Status, Updated, Operations
- 7 products visible on this page (paginated):
  - Sony WH-1000XM5 Wireless Headphones - Published - 14 Feb 2026 09:30
  - CalDigit TS4 Thunderbolt 4 Dock - Published - 14 Feb 2026 09:30
  - Razer DeathAdder V3 Gaming Mouse - Published - 14 Feb 2026 09:30
  - WD Black SN850X 2TB NVMe SSD - Published - 14 Feb 2026 09:30
  - Keychron Q1 Pro Mechanical Keyboard - Published - 14 Feb 2026 09:30
  - Anker PowerCore 26800mAh Portable Charger - Published - 14 Feb 2026 09:30
  - Dell UltraSharp 27 4K USB-C Hub Monitor - Published - 14 Feb 2026 09:30
- All products show "Published" status and "Edit" operation dropdown
- Remaining 5 products (Apple MacBook Air M2, Samsung 65" QLED TV, Bose QC Ultra Earbuds, Logitech MX Master 3S, Corsair DDR5 32GB RAM Kit) on page 2

### 3. `promotions_page.png`

**What it shows:** The Commerce Promotions listing page at `http://localhost/admin/commerce/promotions`.

**Key observations:**
- Page title: "Promotions | Drupal Commerce Store - Mozilla Firefox"
- URL: `http://localhost/admin/commerce/promotions`
- "+ Add promotion" button visible
- List/Reorder tabs visible
- Filter area with Name, Offer type, Coupon code, Status filters
- 3 promotions listed:
  - Save $25 on Orders Over $200 - Fixed amount off the order subtotal - 0/Unlimited usage - Unlimited per customer - Start: Sat, 14 Feb 2026 09:30 - Edit button
  - Welcome 10% Off - Percentage off the order subtotal - 0/Unlimited - Unlimited - Start: Sat, 14 Feb 2026 09:30 - Edit button
  - Electronics 15% Off - Percentage off the order subtotal - 0/Unlimited - Unlimited - Start: Sat, 14 Feb 2026 09:30 - Enable button (correctly disabled/inactive)

## Seeded Data Summary

### Store
- **Name:** Urban Electronics
- **Address:** 456 Market Street, San Francisco, CA 94105, US
- **Default Currency:** USD

### Products (12 total)

| Product | SKU | Price |
|---------|-----|-------|
| Sony WH-1000XM5 Wireless Headphones | SONY-WH1000XM5 | $348.00 |
| Apple MacBook Air M2 13-inch | APPLE-MBA-M2-13 | $1,099.00 |
| Samsung 65-inch 4K QLED Smart TV | SAMSUNG-QN65Q80C | $997.99 |
| Bose QuietComfort Ultra Earbuds | BOSE-QCUE | $299.00 |
| Logitech MX Master 3S Wireless Mouse | LOGI-MXM3S | $99.99 |
| Dell UltraSharp 27 4K USB-C Hub Monitor | DELL-U2723QE | $619.99 |
| Anker PowerCore 26800mAh Portable Charger | ANKER-PC26800 | $65.99 |
| Keychron Q1 Pro Mechanical Keyboard | KEYCHRON-Q1PRO | $199.00 |
| WD Black SN850X 2TB NVMe SSD | WD-SN850X-2TB | $149.99 |
| Razer DeathAdder V3 Gaming Mouse | RAZER-DAV3 | $89.99 |
| CalDigit TS4 Thunderbolt 4 Dock | CALDIGIT-TS4 | $399.99 |
| Corsair Vengeance DDR5 32GB RAM Kit | CORSAIR-DDR5-32G | $94.99 |

### Promotions (3 total)

| Promotion | Type | Coupon Code | Status |
|-----------|------|-------------|--------|
| Welcome 10% Off | Percentage off order subtotal (10%) | WELCOME10 | Active |
| Save $25 on Orders Over $200 | Fixed amount off subtotal ($25) | SAVE25 | Active |
| Electronics 15% Off | Percentage off order subtotal (15%) | None (automatic) | Disabled |

### Customer Accounts

| Username | Email | Password |
|----------|-------|----------|
| johndoe | john.doe@example.com | Customer123! |
| janesmith | jane.smith@example.com | Customer123! |
| mikewilson | mike.wilson@example.com | Customer123! |

## Tasks Defined

### 1. `create_product` (Medium difficulty)
- **Goal:** Create a new product "Organic Bamboo Wireless Charger" (SKU: OBW-CHR-01, $39.99)
- **Start state:** Firefox on Commerce admin Products page
- **Pre-task hook:** Navigates to Products admin page, records initial product count

### 2. `create_coupon` (Medium difficulty)
- **Goal:** Create a new promotion "Summer Sale 20% Off" with coupon code SUMMER20
- **Start state:** Firefox on Commerce admin Promotions page
- **Pre-task hook:** Navigates to Promotions admin page, records initial promotion count

### 3. `add_to_cart` (Easy difficulty)
- **Goal:** Add "Sony WH-1000XM5 Wireless Headphones" to the shopping cart from the storefront
- **Start state:** Firefox on Drupal Commerce product catalog at `/products`
- **Pre-task hook:** Navigates to `/products` page, records initial order/cart count

## Key Setup Log Outputs

### Successful Commerce Module Enable Sequence
```
Enabling Commerce modules...
[success] Successfully enabled: commerce
[success] Successfully enabled: commerce_product
[success] Successfully enabled: commerce_order
[success] Successfully enabled: commerce_cart
[success] Successfully enabled: commerce_checkout
[success] Successfully enabled: commerce_payment
[success] Successfully enabled: commerce_promotion
[success] Successfully enabled: commerce_tax
[success] Successfully enabled: commerce_store
[success] Successfully enabled: commerce_price
```

### Successful Product Seeding Output
```
Created: Sony WH-1000XM5 Wireless Headphones ($348.00)
Created: Apple MacBook Air M2 13-inch ($1099.00)
Created: Samsung 65-inch 4K QLED Smart TV ($997.99)
Created: Bose QuietComfort Ultra Earbuds ($299.00)
Created: Logitech MX Master 3S Wireless Mouse ($99.99)
Created: Dell UltraSharp 27 4K USB-C Hub Monitor ($619.99)
Created: Anker PowerCore 26800mAh Portable Charger ($65.99)
Created: Keychron Q1 Pro Mechanical Keyboard ($199.00)
Created: WD Black SN850X 2TB NVMe SSD ($149.99)
Created: Razer DeathAdder V3 Gaming Mouse ($89.99)
Created: CalDigit TS4 Thunderbolt 4 Dock ($399.99)
Created: Corsair Vengeance DDR5 32GB RAM Kit ($94.99)
```

### Successful Promotion Seeding Output
```
Created: Welcome 10% Off (coupon: WELCOME10)
Created: Save $25 on Orders Over $200 (coupon: SAVE25)
Created: Electronics 15% Off (automatic, disabled)
```

### Database Verification Queries (from final Phase 7 test)
```sql
-- Product count (via Drush sql:query)
SELECT COUNT(*) FROM commerce_product_field_data WHERE status = 1;
-- Result: 12

-- Promotion count
SELECT COUNT(*) FROM commerce_promotion_field_data;
-- Result: 3

-- Coupon count
SELECT COUNT(*) FROM commerce_promotion_coupon WHERE status = 1;
-- Result: 2

-- Store verification
SELECT name FROM commerce_store_field_data;
-- Result: Urban Electronics
```

## Bugs Found and Fixed During Final Testing

### 1. Missing Store Entity in seed_products.php
**Problem:** `seed_products.php` referenced `"stores" => [1]` assuming a store with ID 1 exists, but the store wasn't created before the products. This caused the "Add product" page to show "Products can't be created until a store has been added."
**Fix:** Added store creation (with `online` store type) to the beginning of `seed_products.php` before product creation.

### 2. Missing `mariadb-client` Package
**Problem:** Drush's `sql:query` command requires the `mysql` CLI client on the host system. Without it, Drush reports "The shell command 'mysql' is required but cannot be found."
**Fix:** Added `mariadb-client` to the `apt-get install` in `install_drupal_commerce.sh`.

### 3. Missing `scrot` Package
**Problem:** `scrot` (screenshot tool) was referenced in `task_utils.sh` but not installed.
**Fix:** Added `scrot` to the Firefox/GUI tools install section in `install_drupal_commerce.sh`.

### 4. No Public Product Catalog Page
**Problem:** Drupal Commerce doesn't create a public storefront product listing page by default. The `add_to_cart` task navigated to `/` which showed only a "Welcome" page with no products.
**Fix:** Added creation of a `product_catalog` Drupal View at `/products` in `setup_drupal_commerce.sh`. Updated `add_to_cart/setup_task.sh` to navigate to `/products` instead of `/`.

### 5. Pre-start Hook Timeout
**Known limitation:** The pre_start hook (Composer downloads for Drupal + Commerce) can exceed the QEMU runner's SSH exec timeout (~600s) on slower networks. The framework continues with post_start even after timeout, which may fail if installation is incomplete.

## Post-Audit Fixes (2026-02-14)

An independent audit identified CRITICAL, SEVERE, and MODERATE issues. All have been addressed:

### CRITICAL: Stub Verifiers Replaced with Real Verification
- All 3 verifiers (`create_product`, `create_coupon`, `add_to_cart`) now perform real programmatic verification
- Each verifier reads `/tmp/task_result.json` from the container via `copy_from_env()`
- Multi-criterion scoring (5 checks for create_product, 5 for create_coupon, 4 for add_to_cart)
- Verifiers use the database query functions from `task_utils.sh` (via export_result.sh)

### CRITICAL: export_result.sh Scripts Created
- `tasks/create_product/export_result.sh`: Queries DB for product by title, checks SKU/price/status
- `tasks/create_coupon/export_result.sh`: Queries DB for promotion by name, checks coupon code/status/offer type
- `tasks/add_to_cart/export_result.sh`: Queries DB for cart orders, checks if expected product variation is in cart
- All scripts registered as `post_task` hooks in their respective `task.json` files

### SEVERE: Runtime Boot Resilience Improved
- Added `ensure_services_running()` function to `task_utils.sh` that checks Docker, MariaDB, Apache, Drupal, and Firefox
- All 3 `setup_task.sh` (pre_task hooks) now call `ensure_services_running` before proceeding
- This function can recover from partially-failed post_start hooks by restarting Docker containers, Apache, and relaunching Firefox with Drush ULI
- Changed `setup_task.sh` scripts from hard `exit 1` on failure to soft warnings with retry

### MODERATE: Task Descriptions Made Less Prescriptive
- `create_product`: Removed step-by-step navigation instructions ("Navigate to Commerce > Products > Add product. Fill in the product title...")
- `create_coupon`: Removed step-by-step instructions ("Under the 'Offer' section, select 'Percentage off the order subtotal'...")
- `add_to_cart`: Simplified to focus on the goal rather than the exact clicks
- Descriptions now state what needs to be achieved, not how to achieve it

### Verified End-to-End Pipeline
- Launched fresh environment, completed create_product task interactively
- export_result.sh correctly detected: product count 12→13, title match, SKU=OBW-CHR-01, price=39.99, status=published
- JSON output well-formed and all verifier criteria would pass (score: 100)

## Second Audit Fixes (2026-02-14)

A second independent audit identified additional issues with boot reliability, storefront functionality, missing task completion evidence, and database query errors. All have been addressed:

### SEVERE: /products storefront View had no Add to Cart button
- Changed the `product_catalog` View from field-based rendering (title links only) to entity-based rendering
- View now uses `"row" => ["type" => "entity:commerce_product", "options" => ["view_mode" => "default"]]`
- This renders full product entities including price display and Add to Cart forms
- Added permissions for anonymous/authenticated users: `view commerce_product`, `access cart`, `access checkout`
- Verified with visual_grounding: All 12 products now display with prices and "Add to cart" buttons

### SEVERE: add_to_cart and create_coupon tasks completed with evidence
- **add_to_cart**: Successfully clicked "Add to cart" button for Sony WH-1000XM5. Confirmation banner "Sony WH-1000XM5 Wireless Headphones added to your cart" displayed. Database verified: draft order with 1 item. See `add_to_cart_task_completed.png`.
- **create_coupon**: Successfully created promotion "Summer Sale 20% Off" with 20% percentage off order subtotal. Created coupon code "SUMMER20". Database verified: promotion_id=4, offer_type=order_percentage_off, coupon enabled. See `create_coupon_task_completed.png`.

### MODERATE: create_product description updated
- Added note about two-step workflow: "In Drupal Commerce, the SKU and price are set on a 'product variation', not on the product itself."
- Instructs agent to add a product variation after creating the product

### MODERATE: Boot reliability improved
- **post_start hook**: Added Section 0 that checks if Drupal files are installed (drush exists). If pre_start timed out during Composer downloads, post_start now completes the Composer installation before proceeding.
- **post_start hook**: Added Apache config recovery - recreates `drupal.conf` vhost if missing.
- **task_utils.sh**: `ensure_services_running()` now also: (1) checks/recreates Apache drupal.conf, (2) detects incomplete Drupal installation and completes Composer downloads, (3) restarts Apache if HTTP check fails.
- **Firefox recovery**: Uses `nohup` for Firefox launch commands to prevent blocking.

### Bug fix: Database table names corrected
- `get_order_count()` in task_utils.sh: Changed from `commerce_order_field_data` (doesn't exist) to `commerce_order`
- `export_result.sh` for add_to_cart: Same table name fix for cart count query
- `export_result.sh` for create_coupon: Changed offer type query from `commerce_promotion` to `commerce_promotion_field_data` (where the offer columns actually exist)
- Promotion add URL: Corrected from `/admin/commerce/promotions/add` to `/promotion/add` (Commerce 3.x routes)

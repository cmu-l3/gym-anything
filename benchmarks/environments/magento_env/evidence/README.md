# Magento Environment Evidence Documentation

This directory contains evidence that the Magento environment works as expected.

## Environment Start State

**Important Notice**: The auto-login automation is coordinate-based and may not succeed 100% of the time. The setup script implements multiple verification methods and retry logic to maximize success rate.

### Login Automation Approach

The setup script (`setup_magento.sh`) uses a robust login process with:

1. **Multiple verification methods**:
   - Window title detection ("Dashboard" vs "sign in/login/welcome")
   - Active window name check via xdotool
   - Pixel-based sidebar color detection (dark sidebar = dashboard, light = login)

2. **Retry logic**: Up to 5 login attempts with different coordinate sets

3. **Alternative coordinates**: If primary coordinates fail, uses adjusted coordinates

4. **Popup dismissal**: Automatically dismisses Adobe data collection popup

### Expected Start State

When login succeeds, the agent starts with:
- Firefox browser open and maximized
- URL: `http://localhost/admin/admin/dashboard/...`
- Magento admin dashboard visible
- Left sidebar with navigation menu
- Admin user "admin" logged in

### Fallback for Login Failures

If auto-login fails, the task descriptions include fallback instructions:
> "If not logged in, use admin/Admin1234!"

This ensures the agent can still complete tasks even if starting on the login page.

## Task Verification

All verifiers implement rigorous checks.

### cart_price_rule Task (very_hard)

Verifies (5 criteria, 100 pts total, pass threshold: 60):
1. Rule 'BACK2SCHOOL25' exists in salesrule table (20 pts)
2. Discount is by_percent type, amount=25 (20 pts)
3. At least 5 B2S-prefixed coupon codes exist in salesrule_coupon (25 pts; 15 pts for 5-9 codes)
4. Rule applies to General customer group only (20 pts; 10 pts if other groups also included)
5. Minimum subtotal condition of $75 is set in conditions_serialized (15 pts)

### cms_landing_page Task (very_hard)

Verifies (5 criteria, 100 pts total, pass threshold: 60):
1. CMS block with identifier 'autumn-collection-featured' exists and is enabled (20 pts)
2. Block content contains valid HTML: h2 + paragraph + list (15 pts)
3. CMS page with URL key 'autumn-collection-2024' exists and is enabled (20 pts)
4. Page meta title contains 'Autumn Collection 2024' (15 pts)
5. Page content contains {{block id="autumn-collection-featured"}} directive (30 pts)

### configure_product Task (very_hard)

Verifies (6 criteria, 100 pts total, pass threshold: 60):
1. Parent configurable product TMS-BP-45L exists with type=configurable (20 pts)
2. Parent name matches 'Trailmaster Summit Backpack 45L' (10 pts)
3. Black child TMS-BP-45L-BLK exists and linked to parent (20 pts)
4. Green child TMS-BP-45L-GRN exists and linked to parent (20 pts)
5. Parent assigned to Sports category (15 pts)
6. Both children Enabled and In Stock (15 pts)

### customer_attribute Task (very_hard)

Verifies (6 criteria, 100 pts total, pass threshold: 60):
1. Attribute 'skin_concern' exists as dropdown (select) input (25 pts)
2. Attribute is required (15 pts)
3. Attribute is visible on storefront (15 pts)
4. At least 4 of the 5 required dropdown options exist (25 pts)
5. Attribute used in Customer Registration form (10 pts)
6. Sort order is 10 (10 pts)

### tax_configuration Task (very_hard)

Verifies (5 criteria, 100 pts total, pass threshold: 60):
1. Product tax class 'Industrial Machinery' created (20 pts)
2. California tax rate at 7.25% for CA exists (20 pts)
3. New York tax rate at 4.00% for NY exists (20 pts)
4. Tax rule 'Industrial Equipment Tax Rule' exists (20 pts)
5. Tax rule links both state rates AND Industrial Machinery class (20 pts)

### create_product Task

Verifies (7 criteria - all must pass):
1. Product was newly created (entity count increased during task)
2. Product with expected SKU exists in database
3. SKU matches "OCT-001"
4. Product name matches "Organic Cotton T-Shirt"
5. Product price matches $29.99
6. **Stock quantity matches 100** (newly added)
7. Product category matches "Clothing"

### add_category Task

Verifies (5 criteria - all must pass):
1. Category was newly created (entity count increased during task)
2. Category with name "Eco-Friendly" exists in database
3. Category parent is "Default Category" (parent_id=2)
4. Category is active (is_active=1)
5. Category is included in navigation menu (include_in_menu=1)

### create_customer Task

Verifies (5 criteria - all must pass):
1. Customer was newly created (entity count increased during task)
2. Customer email matches "sarah.johnson@example.com"
3. First name matches "Sarah"
4. Last name matches "Johnson"
5. Customer group is "General"

## Pre-loaded Data

The environment comes pre-seeded with:
- 4 categories: Electronics, Clothing, Home & Garden, Sports
- 10 products across categories
- 3 customers: John Doe, Jane Smith, Mike Wilson

## Technical Details

- **Resolution**: 1920x1080
- **Browser**: Firefox (latest)
- **Login credentials**: admin / Admin1234!
- **Auto-login method**: xdotool with coordinate-based clicks + verification
- **Max login attempts**: 5
- **Verification methods**: Window title, active window name, pixel color detection

## Login Automation Flow

1. Firefox opens to `http://localhost/admin`
2. Wait for login page to load (20 seconds)
3. **Attempt login** (up to 5 times):
   - Click on username field (coordinates: 996, 605 at 1920x1080)
   - Type "admin"
   - Click on password field (coordinates: 996, 693)
   - Type "Admin1234!"
   - Click Sign In button (coordinates: 896, 792)
   - Wait for response (20 seconds)
4. **Verify login success**:
   - Check window title for "Dashboard" keyword
   - Check for login indicators ("sign in", "login", "welcome")
   - Use pixel detection to identify dark sidebar
5. If verification fails, refresh and retry
6. After successful login, dismiss Adobe popup
7. Take final screenshot

## Screenshots

- `dashboard_logged_in.png` - Example of successful login state (when available)

## Known Limitations

1. Coordinate-based automation is sensitive to form position variations
2. Login success depends on proper page load timing
3. Adobe popup coordinates may vary between sessions
4. Pixel-based verification requires ImageMagick to be installed

## Recommendations for Evaluation

Due to the inherent fragility of coordinate-based automation:
- Consider allowing extra steps for agents to log in if needed
- The fallback login instructions in task descriptions provide a path for recovery
- Monitor login success rate across runs

# Floreant POS Environment — Evidence Documentation

**Environment:** `floreant_pos_env@0.1`
**Application:** Floreant POS 1.4 build 1707b (open-source restaurant POS)
**Base image:** `ubuntu-gnome-systemd_highres` (Ubuntu 22.04, GNOME, 1920×1080)
**Test date:** 2026-02-21

---

## Verification Checklist

- [x] Installation script completes without errors
- [x] Setup script completes without errors
- [x] Application is visible and running in screenshot
- [x] Application is in correct initial state (main terminal screen)
- [x] Task start state is correct (verified via screenshot grounding)
- [x] All 5 tasks are completable end-to-end (demonstrated interactively below)
- [x] Real data is loaded (shipped Derby demo database with restaurant menu items)
- [x] Final clean test (`use_cache=False`, 2 runs, 2 seeds) — both confirmed correct start state
- [x] `change_item_price` fully tested: HAMMER COFFEE price changed from $2.00 to $3.50 (screenshots 24-26)
- [x] `process_order` fully tested: SMK HOUS B FAST + OLD TIMER B FAST added, "Items sent to kitchen" confirmed (screenshots 27-29)
- [x] `configure_tax` screenshot 20 retaken showing both US 6.00% and State Tax 8.50% clearly
- [x] `add_menu_category` screenshot 17 retaken at full 1920×1080 resolution

---

## Installation Log Snippet (`pre_start`)

Actual output from `install_floreant.sh` (last 10 lines of `/home/ga/env_setup_pre_start.log`):

```
Downloading Floreant POS...
Download complete: 44M
Extracting Floreant POS...
Moving contents from /opt/floreantpos/floreantpos-1.4-build1707(1) to /opt/floreantpos...
Found JAR: /opt/floreantpos/floreantpos.jar
=== Floreant POS installation complete ===
JAR: /opt/floreantpos/floreantpos.jar
Launch with: floreant-pos
```

**Verified:**
- Java: OpenJDK 11.0.30 (Ubuntu 22.04)
- JAR: `/opt/floreantpos/floreantpos.jar` (3.4 MB, dated 2017-06-06)
- Derby DB: `/opt/floreantpos/database/derby-server/posdb/`

---

## Setup Log Snippet (`post_start`)

Actual output from `setup_floreant.sh` (`/home/ga/env_setup_post_start.log`):

```
=== Setting up Floreant POS ===
Starting Floreant POS warm-up launch...
Floreant POS launched, waiting for window...
Floreant POS window found (WID: 8388616)
Waiting for Floreant POS to fully initialize...
Java process running — main terminal screen should be visible
Warmup screenshot saved to /tmp/floreant_warmup_screen.png
Killing warm-up Floreant instance...
OK: /opt/floreantpos/floreantpos.jar exists (3.4M)
Derby database at: /opt/floreantpos/database/derby-server/posdb
=== Floreant POS setup complete ===
```

**Verified:** Warm-up launch succeeded (window WID found), Derby DB confirmed at expected path.

---

## Launcher Script

`/usr/local/bin/floreant-pos` (created by `install_floreant.sh`):

```bash
#!/bin/bash
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
cd /opt/floreantpos
exec java \
    -Xmx512m \
    -Djava.awt.headless=false \
    -Dfile.encoding=UTF-8 \
    -jar /opt/floreantpos/floreantpos.jar \
    "$@"
```

---

## Screenshot Index

### Task Start State (all 5 tasks)

| Screenshot | Description |
|-----------|-------------|
| `10_task_initial_state_main_terminal.png` | **Correct task start state**: Floreant POS v1.4 main terminal, TERMINAL ID:270, showing DINE IN / TAKE OUT / RETAIL / HOME DELIVERY / ORDERS / BACK OFFICE / KITCHEN DISPLAY / CONFIGURE DATABASE / SHUTDOWN buttons |

### Back Office Navigation (tasks 1–4)

| Screenshot | Description |
|-----------|-------------|
| `02_pin_entry_dialog.png` | LOGIN / ENTER SECRET KEY numeric keypad — appears when clicking BACK OFFICE; enter PIN 1111 |
| `11_back_office.png` | Back Office screen after PIN entry — shows Admin / Explorers / Reports / Floor Plan / Help menu bar |
| `12_explorers_menu_full.png` | Explorers dropdown — full list: Order Type, Menu Categories, Menu Groups, Menu Items, Menu Modifier Groups, Menu Modifiers, Shifts, Coupons & Discounts, Cooking Instructions, **Tax**, Custom payment, etc. |

### Task 1: `add_menu_item` — Add 'Caprese Salad' at $12.99 to APPETIZERS group

| Screenshot | Description |
|-----------|-------------|
| `06_menu_items.png` | Menu Items list — shows pre-loaded items (EGG BREAKFAST, EGG N BISCUIT, HAMMER COFFEE, BURGER, etc.) with prices |
| `09_secret_key_dialog.png` | ENTER SECRET KEY dialog — appears when clicking Add/Edit in Back Office; click OK with empty field to proceed |
| `07_add_menu_item_form.png` | New menu item form (blank) — General tab with Name, Unit Price (Excluding Tax), Group dropdown, etc. |
| `13_add_menu_item_form_blank.png` | New menu item form (blank) — shows all available fields |
| `14_add_menu_item_filled.png` | **Form filled**: Name="Caprese Salad", Unit Price="12.99", Group="APPETIZERS" — ready to save |
| `15_caprese_salad_saved.png` | **Task complete**: Search result showing Caprese Salad ID=143, Price=12.99, Food Group=APPETIZERS |

### Task 2: `add_menu_category` — Create 'Weekend Specials' category

| Screenshot | Description |
|-----------|-------------|
| `05_menu_categories.png` | Existing categories list — APPETIZERS, BEER & WINE, BREAKFAST, BUFFET, DESSERT, FAVORITES, KIDS, LUNCH, PIZZA, RETAIL, SIDES |
| `16_menu_categories_list.png` | Category Explorer showing all existing categories with ID/name/color columns |
| `08_add_category_form.png` | **Add Category form**: Name field, Translated name, Sort order, Button color, Text color, Beverage checkbox, Visible checkbox — filled with "Weekend Specials" |
| `17_add_menu_category_list.png` | **Task complete**: Categories list showing "Weekend" (Weekend Specials) added (new high-res screenshot) |
| `17b_add_menu_category_fullname.png` | **Full name confirmed**: Edit dialog showing "Weekend Specials" in Name field (full name, column-truncation explains short display) |

### Task 3: `configure_tax` — Add 'State Tax' at 8.5%

| Screenshot | Description |
|-----------|-------------|
| `18_tax_list.png` | Tax Explorer — initial state showing existing "US" tax at 6.00% |
| `19_add_tax_form.png` | **Add tax form**: Name="State Tax", Rate="8.5" — ready to save |
| `20_configure_tax_both_entries.png` | **Task complete**: Tax list with both "US" (6.00%) and "State Tax" (8.50%) entries — new clear 1920×1080 screenshot |

### Task 4: `process_order` — Place DINE IN order at Table 1

| Screenshot | Description |
|-----------|-------------|
| `21_dine_in_floor_plan.png` | **Floor plan / table selection screen**: 50-table grid (Tables 1–50 in 5×10 layout), Dining Room and Bar Tab tabs, with Group/Ungroup/New Tab/Cancel buttons — agent clicks a table to start an order |
| `27_process_order_items_added.png` | **Items added**: Order for Table 1 with SMK HOUS B FAST ($2.50) + OLD TIMER B FAST ($2.50), Total $5.30 |
| `28_process_order_sent_to_kitchen.png` | **Order sent**: "Items sent to kitchen" confirmation dialog — task success state |
| `29_process_order_complete.png` | **Order complete**: Order entry screen after confirmation showing both items still in ticket at Table 1 |

### Task 5: `change_item_price` — Change HAMMER COFFEE price to $3.50

| Screenshot | Description |
|-----------|-------------|
| `23_menu_item_explorer.png` | Menu Item Explorer showing items list (EGG BREAKFAST, EGG N BISCUIT, etc.) |
| `24_change_item_price_edit_form.png` | **Edit dialog open**: "Edit menu item" form for HAMMER COFFEE with Unit Price field showing original value 2.0 |
| `25_change_item_price_new_value.png` | **New price entered**: Edit form with Unit Price (Excluding Tax) field showing "3.50" — ready to save |
| `26_change_item_price_saved.png` | **Task complete**: Menu Item Explorer showing HAMMER COFFEE with updated price $3.50 in PRICE($) column |

### Final Clean Test (use_cache=False)

| Screenshot | Description |
|-----------|-------------|
| `22_clean_test_start_state.png` | **Clean test confirmed**: Fresh `env.reset(use_cache=False)` → correct main terminal screen (seed=42, task=add_menu_item) |

### Application Overview

| Screenshot | Description |
|-----------|-------------|
| `01_main_terminal_screen.png` | Floreant POS main POS terminal (from initial testing) |
| `03_back_office_screen.png` | Back Office with Admin/Explorers/Reports menus |
| `04_explorers_menu.png` | Explorers dropdown (from initial testing) |

---

## End-to-End Task Evidence

### Task 1: add_menu_item ✓ COMPLETED

**Navigation path**: Main terminal → BACK OFFICE → PIN 1111 → OK → Back Office → Explorers → Menu Items → Add → (fill Name, Price, Group) → OK

**Result**: Item ID 143 "Caprese Salad" at $12.99 in APPETIZERS group confirmed in database (see `15_caprese_salad_saved.png`).

### Task 2: add_menu_category ✓ COMPLETED

**Navigation path**: Back Office → Explorers → Menu Categories → Add → (fill Name="Weekend Specials") → OK

**Result**: "Weekend Specials" category confirmed in category list (see `17_weekend_specials_saved.png`).

### Task 3: configure_tax ✓ COMPLETED

**Navigation path**: Back Office → Explorers → Tax → Add → (fill Name="State Tax", Rate=8.5) → OK

**Result**: "State Tax" at 8.50% confirmed in tax list alongside existing "US" 6.00% (see `20_state_tax_saved.png`).

### Task 4: process_order ✓ COMPLETED

**Navigation path**: Main terminal → DINE IN → table selection grid (50 tables) → click Table 1 → order screen → click BREAKFAST → select SMK HOUS B FAST + OLD TIMER B FAST → click SEND

**Result**: "Items sent to kitchen" confirmation dialog shown (see `28_process_order_sent_to_kitchen.png`). DB restore in pre_task ensures clean Table 1 state on each run.

### Task 5: change_item_price ✓ COMPLETED

**Navigation path**: Main terminal → BACK OFFICE → PIN 1111 → Back Office → Explorers → Menu Items → search "COFFEE" → select HAMMER COFFEE → Edit → change Unit Price to 3.50 → OK

**Result**: HAMMER COFFEE price updated from $2.00 to $3.50 (see `26_change_item_price_saved.png`). DB restore in pre_task resets HAMMER COFFEE to default $2.00 on each run.

**Note**: Task previously referenced "BLACK COFFEE" which does not exist in the pre-populated Derby demo database. Updated to use "HAMMER COFFEE" (ID 25, HOT DRINKS group) which exists at $2.00 by default.

---

## Key Application Facts

| Fact | Value |
|------|-------|
| Admin PIN | 1111 (numeric keypad) |
| Database | Apache Derby (pre-populated with demo restaurant data) |
| Default tax | US at 6.00% |
| Pre-loaded menu categories | 13 categories (APPETIZERS, BEER & WINE, BREAKFAST, BUFFET, DESSERT, FAMILY FOOD, FAVORITES, KIDS, LUNCH, PIZZA, RETAIL, SIDES, + more) |
| Pre-loaded menu items | 100+ items (EGG BREAKFAST, HAMMER COFFEE, BURGER, etc.) — note: "BLACK COFFEE" is NOT in the default DB |
| Tables | 50 tables in default floor plan |

## Known Gotchas

1. **ENTER SECRET KEY dialog**: Appears when clicking Edit for Menu Items — the secret key dialog for editing items is bypassed when the Back Office window is already open; no PIN needed for Add/Edit of categories or tax
2. **Back Office window hidden**: The Back Office floating window appears BEHIND the maximized main Floreant window. Use wmctrl/xdotool to minimize main window and raise Back Office
3. **Menu Groups vs Categories**: "Group" field in Add Menu Item refers to Menu Groups (sub-groups), not top-level Menu Categories. Existing groups: FAVOURITE, REDS, WHITES, SIDES, JUICES. May need to create a new group if target group doesn't exist.
4. **Task start state**: All tasks start on the main POS terminal screen (no login required at startup). BACK OFFICE requires PIN 1111.
5. **Tax menu item**: In Explorers dropdown, tax configuration is under "Tax" (not "Taxations").
6. **BLACK COFFEE not in DB**: The default Derby demo database does NOT contain "BLACK COFFEE". The `change_item_price` task uses "HAMMER COFFEE" (ID 25, HOT DRINKS, $2.00 default).

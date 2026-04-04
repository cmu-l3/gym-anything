# Bulk Product Import via CSV (`bulk_product_import@1`)

## Overview

This task tests a Magento admin's ability to perform a bulk product import using the built-in CSV Data Transfer functionality. The agent must navigate to the import interface, configure the import settings, upload a pre-prepared CSV file of kitchen products from a supplier, validate the data, and execute the import — a core workflow for online merchants onboarding new inventory.

## Rationale

**Why this task is valuable:**
- Tests interaction with Magento's System > Data Transfer import pipeline, which is distinct from manual product creation
- Requires understanding of CSV validation → import two-step workflow
- Evaluates the agent's ability to handle file upload dialogs and form configuration
- Exercises a completely different feature area from product/category/rule management tasks

**Real-world Context:** An online kitchenware merchant has signed a distribution agreement with a new supplier. The supplier sent a product catalog as a CSV file containing 12 kitchen products. The merchant's order clerk needs to import all products into the Magento catalog using the built-in import tool so they can start selling immediately. This is the standard workflow for adding inventory from new suppliers — far more efficient than creating products one at a time.

## Task Description

**Goal:** Import 12 kitchen products from a supplier CSV file into the Magento catalog using the built-in Data Transfer Import feature, and verify all products are visible in the admin product grid.

**Starting State:** Firefox is open to the Magento admin dashboard. A CSV file containing 12 kitchen products in Magento-compatible format has been placed at `/home/ga/Documents/supplier_kitchenware_catalog.csv`. The store already has categories including "Home & Garden" from prior seeding.

**Expected Actions:**
1. Navigate to the Import page (System > Data Transfer > Import)
2. Select Entity Type: **Products**
3. Set Import Behavior to **Add/Update**
4. Upload the CSV file from `/home/ga/Documents/supplier_kitchenware_catalog.csv`
5. Click **Check Data** to validate the CSV
6. If validation passes, click **Import** to execute the import
7. After import completes, navigate to Catalog > Products to confirm the new products appear in the grid

**Final State:** All 12 products from the CSV file exist in the Magento catalog with correct names, prices, and stock quantities. Products are enabled and visible in "Catalog, Search."

## Verification Strategy

### Primary Verification: Database Record Check

The verifier queries the Magento database for each of the 12 expected SKUs and validates:

1. **Product existence** — SKU exists in `catalog_product_entity`
2. **Product name** — matches expected name from `catalog_product_entity_varchar` (name attribute)
3. **Product price** — matches expected price from `catalog_product_entity_decimal` (price attribute)
4. **Stock quantity** — matches expected qty from `cataloginventory_stock_item`
5. **Product enabled** — `product_online` / status = 1 (enabled)
6. **Visibility** — set to "Catalog, Search" (visibility = 4)

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Products Imported (existence) | 40 | 3.33 pts per SKU found (12 SKUs). Full credit at 12, proportional otherwise. Minimum 8 for any credit. |
| Correct Prices | 25 | ~2.08 pts per product with matching price (±$0.01 tolerance) |
| Correct Stock Quantities | 20 | ~1.67 pts per product with matching qty (exact match required) |
| Products Enabled & Visible | 15 | All imported products have status=1 and visibility=4. |
| **Total** | **100** | |

**Pass Threshold:** 60 points
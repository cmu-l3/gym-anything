# Task: Update Purchase Prices

## Overview

A purchasing manager at GardenWorld receives an updated pricing agreement from Seed Farm Inc. for Q2 2026. Three products have new negotiated purchase prices that must be recorded in the iDempiere purchase price list so that future purchase orders automatically use the correct costs.

This task tests the agent's ability to navigate iDempiere's price list management system — a module distinct from the product catalog — and update multiple product prices within a specific price list version.

## Goal

Update the standard prices on the **Purchase 2003** price list version for three products:

| Product | New Standard Price |
|---------|-------------------|
| Mulch 10# | $3.15 |
| Fertilizer #50 | $19.50 |
| Grass Seed Container | $52.00 |

All three prices must be saved and reflected in the iDempiere database.

## Credentials

- **URL**: https://localhost:8443/webui/
- **User**: GardenAdmin
- **Password**: GardenAdmin

## Success Criteria

- Mulch 10# standard price on Purchase 2003 = $3.15 (±$0.05)
- Fertilizer #50 standard price on Purchase 2003 = $19.50 (±$0.05)
- Grass Seed Container standard price on Purchase 2003 = $52.00 (±$0.10)
- All three prices must have changed from their baseline values

## Verification Strategy

The verifier queries `m_productprice` directly for each product on price list version 103 (Purchase 2003), compares the `pricestd` field against the expected values, and also verifies each price changed from the initial baseline recorded at task start.

**Scoring (100 points):**
- Mulch 10# updated correctly: 33 points
- Fertilizer #50 updated correctly: 33 points
- Grass Seed Container updated correctly: 34 points
- Pass threshold: 70 points (at least 2 of 3)

## Schema Reference

- `m_pricelist_version` — price list versions (version_id=103 = "Purchase 2003")
- `m_productprice` — product prices per version (pricestd = standard cost)
- Product IDs: Mulch 10#=137, Fertilizer #50=136, Grass Seed Container=125

## Key Challenge

In iDempiere, price lists are managed through a dedicated **Price List** window (not the Product form). The agent must navigate to the correct module, find the Purchase 2003 version, locate each product within it, update the price, and save — without being told which menu to use or which dialog to open.

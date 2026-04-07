# Task: Update Export Price List and Create Export Sales Order

## Overview

GardenWorld is expanding its export sales channel for patio furniture. A sales operations manager must first update the export price list with new pricing negotiated for international markets, and then create a sales order for export customer Patio Fun, Inc. using those updated export prices.

This task requires navigating two distinct iDempiere modules: Price List management (to update export prices) and Sales Orders (to create the export order with the correct price list).

## Goal

**Part 1 — Update Export 2003 Price List:**
| Product | New Standard Price |
|---------|-------------------|
| Patio Chair | $32.00 |
| Patio Table | $65.00 |
| Patio Sun Screen | $21.50 |

**Part 2 — Create Export Sales Order for Patio Fun, Inc.:**
| Product | Quantity |
|---------|----------|
| Patio Chair | 20 |
| Patio Table | 8 |
| Patio Sun Screen | 12 |

The sales order must use the **Export price list** (not Standard).

## Credentials

- **URL**: https://localhost:8443/webui/
- **User**: GardenAdmin
- **Password**: GardenAdmin

## Success Criteria

- Patio Chair price on Export 2003 (version_id=105) updated to $32.00 (±$0.10)
- Patio Table price on Export 2003 updated to $65.00 (±$0.10)
- Patio Sun Screen price on Export 2003 updated to $21.50 (±$0.10)
- All three prices changed from their baseline values
- New sales order created for Patio Fun, Inc. (c_bpartner_id=121) after task start
- Order has Patio Chair qty ≥ 20, Patio Table qty ≥ 8, Patio Sun Screen qty ≥ 12

## Verification Strategy

**Scoring (100 points):**
- Patio Chair export price updated to $32.00: 12 points
- Patio Table export price updated to $65.00: 12 points
- Patio Sun Screen export price updated to $21.50: 11 points
- New SO created for Patio Fun, Inc.: 15 points
- Patio Chair qty ≥ 20: 17 points
- Patio Table qty ≥ 8: 17 points
- Patio Sun Screen qty ≥ 12: 16 points

Pass threshold: 70 points

## Schema Reference

- `m_pricelist_version` — version_id=105 is "Export 2003", pricelist_id=103
- `m_productprice` — product prices per version (pricestd column)
- `c_order` — sales orders; m_pricelist_id=103 for Export price list
- `c_orderline` — order lines (m_product_id, qtyordered)
- Products: Patio Chair=133, Patio Table=134, Patio Sun Screen=135
- Customer: Patio Fun, Inc. c_bpartner_id=121

## Key Challenges

1. **Price list navigation**: Export prices are in a separate Price List window. The agent must find the "Export" price list, navigate to version "Export 2003", and update prices for three products — without being told which menu item to use.

2. **Correct price list on order**: When creating the sales order, the agent must explicitly select the Export price list instead of the default Standard price list. This is a judgment call: the task description implies export pricing, but the agent must know to look for the price list selector on the Sales Order form.

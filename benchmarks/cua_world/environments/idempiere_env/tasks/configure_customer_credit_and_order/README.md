# Task: Configure Customer Credit & Payment Terms, Then Create Sales Order

## Overview

Agri-Tech, an existing GardenWorld customer, has undergone a financial review and been approved for a larger credit line and updated payment terms. An operations manager must update the customer's account configuration in iDempiere and then create a sales order to fulfill their next purchase.

This task tests the agent's ability to navigate two distinct areas of iDempiere: Business Partner customer configuration (spanning credit management and payment terms tabs) and the Sales Order module.

## Goal

**Part 1 — Update Agri-Tech Customer Account:**
- Set credit limit to **$15,000**
- Set payment terms to **2%10 Net 30**

**Part 2 — Create a Sales Order for Agri-Tech:**
| Product | Quantity |
|---------|----------|
| Azalea Bush | 8 |
| Holly Bush | 6 |

The sales order can remain in Draft status.

## Credentials

- **URL**: https://localhost:8443/webui/
- **User**: GardenAdmin
- **Password**: GardenAdmin

## Success Criteria

- Agri-Tech (c_bpartner_id=200000) has creditlimit ≥ $14,000 (at least $15,000 set)
- Agri-Tech payment terms = 2%10 Net 30 (c_paymentterm_id=106)
- A new sales order exists for Agri-Tech created after task start
- Order has Azalea Bush (product_id=128) with qty ≥ 8
- Order has Holly Bush (product_id=129) with qty ≥ 6

## Verification Strategy

**Scoring (100 points):**
- Credit limit ≥ $14,000: 25 points
- Payment terms = 2%10 Net 30: 25 points
- New sales order created for Agri-Tech: 20 points
- Azalea Bush line qty ≥ 8: 15 points
- Holly Bush line qty ≥ 6: 15 points

Pass threshold: 70 points

## Schema Reference

- `c_bpartner` — customer config: creditlimit, c_paymentterm_id, socreditstatus
- `c_paymentterm` — payment terms (id=106 is "2%10 Net 30")
- `c_order` — sales orders (issotrx='Y', c_bpartner_id=200000)
- `c_orderline` — order lines (m_product_id, qtyordered)
- Agri-Tech: c_bpartner_id=200000, search key='Agri-Tech'

## Key Challenge

Credit limit and payment terms live in **different areas** of the Business Partner window (Customer tab / Credit Management section). After updating both, the agent must then **switch to a completely different module** (Sales Orders) and create a new order, selecting the correct customer and adding two product lines.

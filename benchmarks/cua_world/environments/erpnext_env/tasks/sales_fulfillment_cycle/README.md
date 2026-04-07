# Task: sales_fulfillment_cycle

**Difficulty**: very_hard
**Environment**: erpnext_env
**Occupation alignment**: Customer Service Representatives (importance=89, GDP=$1.25B)

## Overview

Consumers and Consumers Express has a submitted Sales Order for 20 Wind Turbines ($21 each) and 10 Wind Mill A Series ($28 each) — total $700. The agent must complete the full order fulfillment cycle.

## Setup State

- Customer "Consumers and Consumers Express" is created
- Wind Turbine and Wind Mill A Series items are stocked (inventory pre-loaded)
- **A submitted Sales Order (SO) for the above items is ready**
- Browser is open to the Sales Order list

## Required Agent Actions (in order)

1. Find the submitted SO for Consumers and Consumers Express
2. Create a **Delivery Note** from the SO (ship goods to customer)
3. Create a **Sales Invoice** from the DN or SO (bill the customer)
4. Create a **Payment Entry** from the SI (record customer payment)
5. Verify customer outstanding balance reaches $0

## Scoring (100 pts, pass >= 70)

| Criterion | Points | Check |
|-----------|--------|-------|
| C1: Delivery Note submitted, Wind Turbine qty>=20, Wind Mill qty>=10 | 25 | Export queries DN items |
| C2: Sales Invoice submitted, grand_total >= $660 | 25 | Export queries SI |
| C3: Payment Entry (Receive) submitted for customer | 25 | Export queries PE |
| C4: Customer outstanding balance = $0 | 25 | Sum of SI outstanding_amount |

## Key ERPNext Workflow Notes

- From a submitted SO, click **Create > Delivery Note** to ship goods
- From a submitted DN (or SO), click **Create > Sales Invoice**
- From a submitted SI, click **Make > Payment Entry** to record customer payment
- Payment type should be "Receive" for customer payments

## Files

- `task.json` — task metadata and init config
- `setup_task.sh` — creates customer, items, stocks inventory, submits SO
- `export_result.sh` — queries ERPNext for DN/SI/PE, writes `/tmp/sales_fulfillment_cycle_result.json`
- `verifier.py` — scores based on exported result JSON

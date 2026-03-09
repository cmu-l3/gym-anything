# Task: Three-Step Delivery Fulfillment

## Occupation Context
**Warehouse Manager / Operations Manager** — Warehouse managers in Odoo configure warehouse operations (routes, steps, zones) and manage the physical flow of goods. Implementing multi-step operations is a standard professional task when upgrading warehouse efficiency.

## Task Overview (Hard)
The agent must: (1) configure the main warehouse to use 3-step outgoing shipments (Pick → Pack → Ship), then (2) create a complete sales order for 3 real packaging/industrial tape products to customer TechSource Procurement LLC, and (3) process the delivery through all three sequential stages until fully shipped.

## Starting State
- Warehouse is configured for 1-step (ship-only) outgoing operations
- Three real commercial products exist with sufficient stock:
  - 3M 2050 General Purpose Masking Tape 2in (100 units in WH/Stock)
  - Protective Foam Roll 1/4in (80 units in WH/Stock)
  - Scotch 3750 Heavy Duty Packing Tape 2in (60 units in WH/Stock)
- Customer "TechSource Procurement LLC" exists in Odoo

## Expected End State
1. Warehouse `delivery_steps = 'pick_pack_ship'`
2. A confirmed sales order exists for TechSource Procurement LLC
3. Three pickings exist for the SO: one PICK, one PACK, one OUT (delivery)
4. All three pickings are in `state = 'done'`
5. Products have left WH/Stock (quantities reduced accordingly)

## Why This Is Hard
- Agent must know where to find warehouse configuration in Odoo (not obvious)
- Must understand the concept of 3-step delivery routing
- Must navigate through 3 separate sequential operations, each requiring its own validation
- Odoo creates the pick/pack/ship operations automatically only after 3-step is configured AND the SO is confirmed
- Each step has different UI and validation flow (picking from locations, packing items, shipping)

## Difficulty
**Hard** — targets and quantities are given, but agent must find warehouse settings, configure them, create the order, and navigate 3 sequential operations.

## Verification Strategy
- 20 pts: Warehouse configured for 3-step delivery (pick_pack_ship)
- 15 pts: Sales order created for TechSource Procurement LLC
- 15 pts: Pick operation completed (done)
- 15 pts: Pack operation completed (done)
- 20 pts: Ship/delivery operation completed (done)
- 15 pts: Correct quantities (20+15+10) fully processed

Pass threshold: 65/100

## Key Odoo Tables
- `stock_warehouse`: Contains `delivery_steps` field (ship_only/pick_ship/pick_pack_ship)
- `sale_order`: Sales orders
- `stock_picking`: Transfer operations (state: confirmed/assigned/done)
- `stock_picking_type`: Defines operation type (code: outgoing/internal)
- `stock_move`: Individual product movements within pickings

## Data Sources
Real commercial packaging products:
- 3M 2050 General Purpose Masking Tape: 3M Industrial Tapes catalog
- Protective Foam Roll 1/4in x 12in x 10ft: Standard polyethylene protective foam
- Scotch 3750 Heavy Duty Packing Tape: 3M Scotch packaging products catalog

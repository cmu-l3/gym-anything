# Task: herd_exit_batch_processing

## Overview

**Difficulty**: Very Hard
**Role**: Livestock Manager
**Domain**: Herd Management — Exit Declaration & Sale Invoice
**Environment**: Ekylibre FMIS, GAEC JOULIN demo data (171 real bovines)

## Background

In French livestock farming, all cattle movements must be declared to BDNI (Base de Données Nationale d'Identification) within 7 days. When cattle leave the farm for slaughter, the farmer must:
1. Record the exit in their livestock management system (here: Ekylibre)
2. Issue a sale invoice to the abattoir/buyer
3. Prepare the ATM (Attestation de Transport et de Mouvement) document

GAEC JOULIN has 171 bovines. The farm is participating in a restructuring subsidy programme that requires culling the oldest animals first.

## Goal

The agent must:
1. Browse the animals list, identify the 5 with the earliest birth dates
2. For each of the 5 oldest animals: record exit date 2024-03-01, reason "Abattage", and a destination buyer
3. Create a consolidated sale invoice for the 5 animals dated 2024-03-01

## Success Criteria

- **Criterion 1** (30 pts): ≥5 animals have exit_at recorded after task start
- **Criterion 2** (25 pts): Exit records reference the date 2024-03-01
- **Criterion 3** (25 pts): ≥1 new sale invoice (sale_invoice or sale_order) created after task start
- **Criterion 4** (20 pts): The 5 exited animals are among the oldest in the herd (born before 2010)

**Pass threshold**: 60 points
**Mandatory**: ≥5 animals with exit_at set after task start

## Verification Strategy

The export script queries:
- `products` / `animals` for records with updated `exit_at` after task_start
- `sale_invoices` for new records after task_start
- Cross-references exit dates and amounts

## Schema Reference

```sql
SET search_path TO demo, lexicon, public;

-- Find animals and their birth/exit dates (animals are products in Ekylibre)
-- In Ekylibre, animals may be in 'animals' table OR 'products' with type indicator

-- Try the animals table
SELECT id, name, born_at, exit_at, created_at FROM animals ORDER BY born_at LIMIT 10;

-- Alternatively, products table with animal variant
SELECT id, name, born_at, dead_at FROM products
WHERE type = 'Animal' ORDER BY born_at LIMIT 10;

-- Sale invoices
SELECT id, number, invoiced_at, state, amount, created_at FROM sale_invoices ORDER BY id DESC LIMIT 10;
```

## Notes

- GAEC JOULIN has 171 real bovines loaded from the first_run demo data
- In Ekylibre, animals appear in the `/backend/animals` section
- The exit form is accessed via the animal's detail page → "Sortie" button
- Sale invoices are under /backend/sale_invoices

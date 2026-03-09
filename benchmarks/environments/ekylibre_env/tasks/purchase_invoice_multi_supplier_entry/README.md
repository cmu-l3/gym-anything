# Task: purchase_invoice_multi_supplier_entry

## Overview

**Difficulty**: Very Hard
**Role**: Farm Procurement Manager / Farm Accountant
**Domain**: Purchasing — Multi-Supplier Invoice Entry & Accounting Integration
**Environment**: Ekylibre FMIS, GAEC JOULIN demo data (99 real supplier entities)

## Background

French farms must record all purchase invoices in their accounting system. Under the Plan Comptable Agricole, agricultural inputs map to specific account codes:
- 60100: Semences et plants (seeds)
- 60200: Engrais et amendements (fertilizers)
- 60300: Produits de protection des cultures (pesticides)
- 44566: TVA déductible sur autres biens (deductible VAT)
- 40100: Fournisseurs (accounts payable)

When a purchase invoice is validated in Ekylibre, the system automatically creates the corresponding journal entries (debit 601/602/603, credit 401).

## Goal

The agent must:
1. Identify 3 distinct supplier entities in the system
2. Create 3 purchase invoices (one per supplier) for different input categories
3. Validate at least 2 invoices to trigger accounting journal entry creation

## Success Criteria

- **Criterion 1** (30 pts): ≥3 new purchase invoices created after task start
- **Criterion 2** (30 pts): Invoices reference ≥3 distinct supplier entities
- **Criterion 3** (25 pts): ≥2 invoices are in validated/confirmed state
- **Criterion 4** (15 pts): All invoices dated 2024-01-20

**Pass threshold**: 60 points
**Mandatory**: ≥2 new purchase invoices from distinct suppliers

## Verification Strategy

Export script queries:
- `purchase_invoices` for records created after task_start
- Checks `supplier_id` for distinctness
- Checks `state` field for 'confirmed'/'validated' status

## Schema Reference

```sql
SET search_path TO demo, lexicon, public;

-- Purchase invoices
SELECT id, number, invoiced_at, supplier_id, state, amount, created_at
FROM purchase_invoices ORDER BY id DESC LIMIT 10;

-- Supplier entities
SELECT id, full_name, supplier_account_id
FROM entities WHERE supplier_account_id IS NOT NULL LIMIT 20;

-- Purchase invoice items
SELECT pi.id, pi.number, pit.variant_id, pit.quantity, pit.amount
FROM purchase_invoices pi
JOIN purchase_invoice_items pit ON pit.purchase_invoice_id = pi.id
ORDER BY pi.id DESC LIMIT 20;
```

## Notes

- 99 real entities from GAEC JOULIN, many with supplier role
- The /backend/purchase_invoices route works (not /backend/purchases which 404s)
- Tax rates are set per invoice line item in Ekylibre

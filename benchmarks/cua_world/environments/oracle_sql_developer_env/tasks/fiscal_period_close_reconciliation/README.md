# Fiscal Period Close Reconciliation

## Domain Context

Corporate controllers and treasurers perform quarterly fiscal close processes that require identifying and correcting general ledger errors before financial statements can be consolidated and filed. Common close tasks include detecting unbalanced journal entries, removing duplicate postings, eliminating intercompany transactions, and reclassifying misbooked entries. This task reflects the real-world workflow that Treasurers, Controllers, and Financial Managers at mid-size manufacturing companies perform using Oracle ERP systems.

**Occupation**: Treasurers and Controllers (SOC 11-3031)
**Industry**: Manufacturing
**GDP Contribution**: $19.9B annually

## Task Overview

The FISCAL schema contains the general ledger for a mid-size manufacturing company. During the Q3 2024 close process, the accounting team flagged discrepancies that must be resolved:

1. **Unbalanced Journal Entry**: Entry JE-2024-0047 has total debits that do not equal total credits (off by $5,000). Identify and correct the imbalance.
2. **Duplicate Journal Entry**: Entry JE-2024-0023 has been posted twice (duplicate as JE-2024-0023-DUP). Remove the duplicate.
3. **Uneliminated Intercompany Transaction**: A $75,000 intercompany sale between the parent and subsidiary was not eliminated for consolidation. Create the elimination entry.
4. **Misclassified Capital Expenditure**: A $25,000 equipment purchase was debited to Utilities Expense instead of Property, Plant & Equipment. Reclassify the entry.
5. **Create Consolidated Views**: Build a TRIAL_BALANCE_MV materialized view using ROLLUP for subtotals and a CONSOLIDATED_REPORT_VW income statement view.
6. **Export Results**: Export the corrected trial balance to CSV.

## Credentials

- Fiscal schema: `fiscal_admin` / `Fiscal2024`
- System: `system` / `OraclePassword123`

## Success Criteria

- All 4 GL errors identified and corrected
- TRIAL_BALANCE_MV materialized view exists, uses ROLLUP, and balances (debits = credits)
- CONSOLIDATED_REPORT_VW view exists with income statement structure
- CSV file exported to `/home/ga/fiscal_close_results.csv` with account categories
- SQL Developer GUI was used

## Verification Strategy

- **Error corrections**: Direct SQL queries verify each specific error is resolved (entry balances, duplicate removed, IC elimination completed, PP&E reclassified)
- **Materialized view**: ALL_MVIEWS checked for existence, balance verified, query text checked for ROLLUP/CUBE usage
- **Consolidated view**: ALL_VIEWS checked for existence
- **CSV**: File existence, size, and content keywords verified
- **GUI**: SQL history, MRU cache, active sessions

## Schema Reference

```sql
FISCAL_ADMIN.CHART_OF_ACCOUNTS (account_id, account_number, account_name, account_category, account_type, normal_balance)
FISCAL_ADMIN.ENTITIES (entity_id, entity_name, entity_type)
FISCAL_ADMIN.COST_CENTERS (center_id, center_code, center_name, entity_id)
FISCAL_ADMIN.JOURNAL_ENTRIES (entry_id, entry_number, entry_date, description, posted_by, status, entity_id, is_intercompany)
FISCAL_ADMIN.JOURNAL_LINES (line_id, entry_id, account_id, center_id, debit_amount, credit_amount, line_description)
FISCAL_ADMIN.INTERCOMPANY_ELIMINATIONS (elim_id, source_entry_id, target_entry_id, amount, status)
```

## Difficulty: very_hard

The agent must independently:
- Discover which specific journal entries contain errors (not told entry IDs directly in task description)
- Understand double-entry accounting rules to fix imbalances
- Know that intercompany transactions require elimination entries
- Distinguish capital expenditures from operating expenses
- Write Oracle-specific SQL for materialized views with ROLLUP
- Navigate SQL Developer to create views and export data

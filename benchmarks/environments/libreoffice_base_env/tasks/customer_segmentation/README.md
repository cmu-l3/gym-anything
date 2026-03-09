# customer_segmentation

## Overview

**Domain**: Marketing analytics / customer relationship management
**Occupation context**: Marketing analysts and customer service administrators use the Chinook music store database to segment customers by purchasing behavior, enabling targeted promotions and loyalty programs.

The Chinook database has 59 real customers with full invoice histories. The analyst must build a customer segmentation system: compute lifetime value, define tiers, and assign customers to tiers.

## Goal

The end state must include all of the following in the `chinook.odb` LibreOffice Base file:

1. **A saved query named `CustomerLifetimeValue`** — joins the `Customer` and `Invoice` tables, GROUP BY customer, and computes: `CustomerId`, `FirstName`, `LastName`, `Country`, `OrderCount` (number of invoices), `TotalSpent` (SUM of Invoice.Total), `AvgOrderValue` (average invoice amount).

2. **A table named `CustomerTier`** with at least columns: `TierId` (integer, primary key), `TierName` (text), `MinSpend` (numeric), `MaxSpend` (numeric), `Description` (text).

3. **At least 4 rows in `CustomerTier`** representing distinct customer segments. Reasonable tiers based on Chinook customer spend (which ranges from ~$0 to ~$50 total): e.g., Bronze (< $10), Silver ($10–$20), Gold ($20–$40), Platinum (> $40).

4. **A saved query named `CustomerTierAssignment`** — assigns each customer to a tier based on their total spend. Must reference or join with customer spending data and the `CustomerTier` table (or equivalent CASE/IIF logic).

5. **A report named `Customer Analysis`** (name must contain "Customer") — presenting customer segmentation results.

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| `CustomerLifetimeValue` query with joins + GROUP BY | 25 | Parse content.xml, check JOIN + GROUP BY + aggregates |
| `CustomerTier` table created | 20 | Parse database/script for CREATE TABLE |
| CustomerTier has 4+ rows | 15 | Count INSERTs in database/script |
| `CustomerTierAssignment` query | 25 | Parse content.xml, check tier/customer references |
| Report containing "Customer" created | 15 | Parse content.xml/ZIP for reports |
| **Total** | **100** | Pass threshold: 70 |

## Schema Reference

Relevant Chinook tables:
- `Customer` (CustomerId INTEGER PK, FirstName, LastName, Company, Address, City, State, Country, PostalCode, Phone, Fax, Email, **SupportRepId**)
- `Invoice` (InvoiceId, **CustomerId**, InvoiceDate, BillingAddress, BillingCity, BillingState, BillingCountry, BillingPostalCode, Total)

Example CustomerLifetimeValue query:
```sql
SELECT c."CustomerId", c."FirstName", c."LastName", c."Country",
       COUNT(i."InvoiceId") AS OrderCount,
       SUM(i."Total") AS TotalSpent,
       AVG(i."Total") AS AvgOrderValue
FROM "Customer" c
JOIN "Invoice" i ON c."CustomerId" = i."CustomerId"
GROUP BY c."CustomerId", c."FirstName", c."LastName", c."Country"
ORDER BY TotalSpent DESC
```

Chinook customer spend stats (for realistic tier boundaries):
- Minimum total spend: ~$3.96 (customers with 1-2 invoices)
- Maximum total spend: ~$49.62
- Median: ~$39-40

## Credentials

- **Login**: Username `ga`, password `password123`
- **Application**: LibreOffice Base with `/home/ga/chinook.odb`

# genre_revenue_queries

## Overview

**Domain**: Music store database administration
**Occupation context**: Administrative Assistants / Database Analysts at a digital music store maintain the Chinook sales database, producing revenue reports for management.

The Chinook database stores sales data for a digital music store: artists, albums, tracks, invoices, and customer records. Management wants a revenue analysis dashboard. The analyst must build the required database objects using LibreOffice Base.

## Goal

The end state must include all of the following in the `chinook.odb` LibreOffice Base file:

1. **A saved query named `GenreRevenue`** — computes total revenue per music genre by joining the `InvoiceLine`, `Track`, and `Genre` tables; must GROUP BY genre and compute a revenue aggregate (SUM of unit price × quantity).

2. **A saved query named `CountryRevenue`** — computes total sales revenue per billing country by joining the `Invoice` and `Customer` tables; must GROUP BY billing country with a revenue aggregate.

3. **A table named `RevenueTarget`** — stores annual revenue targets per genre per quarter, with at least columns: `TargetId` (integer, primary key), `Genre` (text), `AnnualTarget` (numeric), `Quarter` (integer).

4. **At least 4 data rows inserted into `RevenueTarget`** — use realistic genre names (e.g., Rock, Jazz, Classical, Pop) and realistic target dollar amounts.

5. **A report named `Revenue Analysis`** (or similar containing "Revenue") — summarizing the genre revenue data.

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| `GenreRevenue` query exists with correct joins/aggregation | 25 | Parse content.xml for query name + check command keywords |
| `CountryRevenue` query exists with correct joins/aggregation | 25 | Parse content.xml for query name + check command keywords |
| `RevenueTarget` table created | 20 | Parse database/script for CREATE TABLE |
| `RevenueTarget` has 4+ rows | 15 | Count INSERT statements in database/script |
| Report containing "Revenue" created | 15 | Parse content.xml/ZIP for reports section |
| **Total** | **100** | Pass threshold: 70 |

## Schema Reference

Relevant Chinook tables:
- `Genre` (GenreId INTEGER PK, Name VARCHAR)
- `Track` (TrackId, Name, AlbumId, MediaTypeId, **GenreId**, Composer, Milliseconds, Bytes, UnitPrice)
- `InvoiceLine` (InvoiceLineId, InvoiceId, **TrackId**, UnitPrice, Quantity)
- `Invoice` (InvoiceId, **CustomerId**, InvoiceDate, BillingAddress, **BillingCountry**, Total)
- `Customer` (CustomerId, FirstName, LastName, **Country**, ...)

Example query structure for GenreRevenue:
```sql
SELECT g."Name" AS GenreName, SUM(il."UnitPrice" * il."Quantity") AS Revenue
FROM "Genre" g
JOIN "Track" t ON g."GenreId" = t."GenreId"
JOIN "InvoiceLine" il ON t."TrackId" = il."TrackId"
GROUP BY g."GenreId", g."Name"
ORDER BY Revenue DESC
```

## Credentials

- **Login**: Username `ga`, password `password123`
- **Application**: LibreOffice Base with `/home/ga/chinook.odb`

## Edge Cases

- HSQLDB requires double-quoted identifiers for table/column names
- The ODB file is a ZIP archive; it is parsed after LibreOffice exits
- The verifier checks for query names case-insensitively
- Tables are verified by parsing the HSQLDB `database/script` after SHUTDOWN

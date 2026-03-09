# commission_tracking_system

## Overview

**Domain**: HR administration / payroll
**Occupation context**: Administrative Assistants and HR coordinators track employee sales commissions. The Chinook database contains real sales rep data (Employees table) and their associated customer invoices. Management needs a commission tracking system built in the existing database.

## Goal

The end state must include all of the following in the `chinook.odb` LibreOffice Base file:

1. **A table named `CommissionRate`** with at least columns: `RateId` (integer, primary key), `EmployeeId` (integer), `CommissionPct` (numeric, e.g., 0.05 for 5%), `EffectiveDate` (date).

2. **Commission rates inserted for EmployeeIds 3, 4, and 5** — these are the three Chinook sales representatives (Jane Peacock, Margaret Park, Steve Johnson). Each must have at least one row in `CommissionRate`.

3. **A saved query named `RepSalesTotal`** — joins the `Employee`, `Customer`, and `Invoice` tables to compute total sales amount per sales rep. Must include employee name and GROUP BY employee.

4. **A saved query named `CommissionDue`** — calculates the commission dollar amount owed to each rep by joining (or referencing) `RepSalesTotal` and `CommissionRate`; must reference both employee data and the commission percentage.

5. **A form named `Commission Entry`** (name must contain "Commission") — a data-entry form for adding/editing commission rate records in the `CommissionRate` table.

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| `CommissionRate` table created | 20 | Parse database/script for CREATE TABLE |
| Rows for EmployeeIds 3, 4, 5 inserted | 20 | Count INSERTs in database/script for CommissionRate |
| `RepSalesTotal` query with joins | 25 | Parse content.xml, check JOIN + GROUP BY + Invoice |
| `CommissionDue` query referencing both | 20 | Parse content.xml, check commission + employee refs |
| Form containing "Commission" created | 15 | Parse content.xml/ZIP for forms |
| **Total** | **100** | Pass threshold: 70 |

## Schema Reference

Relevant Chinook tables:
- `Employee` (EmployeeId INTEGER PK, LastName, FirstName, Title, **ReportsTo**, BirthDate, HireDate, ...)
  - EmployeeId 1: Andrew Adams (General Manager)
  - EmployeeId 2: Nancy Edwards (Sales Manager)
  - EmployeeId 3: Jane Peacock (Sales Support Agent) ← sales rep
  - EmployeeId 4: Margaret Park (Sales Support Agent) ← sales rep
  - EmployeeId 5: Steve Johnson (Sales Support Agent) ← sales rep
- `Customer` (CustomerId, FirstName, LastName, **SupportRepId** → Employee.EmployeeId, ...)
- `Invoice` (InvoiceId, **CustomerId**, InvoiceDate, Total, ...)

Example RepSalesTotal query:
```sql
SELECT e."EmployeeId", e."FirstName" || ' ' || e."LastName" AS RepName,
       SUM(i."Total") AS TotalSales
FROM "Employee" e
JOIN "Customer" c ON e."EmployeeId" = c."SupportRepId"
JOIN "Invoice" i ON c."CustomerId" = i."CustomerId"
GROUP BY e."EmployeeId", e."FirstName", e."LastName"
```

## Credentials

- **Login**: Username `ga`, password `password123`
- **Application**: LibreOffice Base with `/home/ga/chinook.odb`

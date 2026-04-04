# Task: sakila_audit_system

## Domain Context
Software developers and DBAs frequently implement automated audit trails (using triggers)
and business logic routines (using stored procedures) in production MySQL databases.
A trigger-based audit log and a tier-classification stored procedure represent core database
programming skills used in real e-commerce, SaaS, and ERP applications.

## Occupation Context
Primary occupations: Software Developers ($3.4B GDP), Database Administrators ($668M GDP)
Rationale: "Essential for querying, designing, and managing application databases." —
"The primary interface for creating, configuring, querying, and managing database structures."

## Task Goal
1. Create AFTER UPDATE trigger tr_customer_audit on sakila.customer that logs changes to
   sakila.customer_audit_log (customer_id, old_email, new_email, changed_at)
2. Create stored procedure sp_calculate_loyalty_tiers() that classifies customers:
   Bronze (0-5 rentals), Silver (6-20), Gold (21+) into sakila.customer_loyalty
3. Test the trigger by updating >= 5 customer email addresses
4. Call sp_calculate_loyalty_tiers()
5. Export customer_loyalty to /home/ga/Documents/exports/customer_loyalty.csv

## Starting State (set up by setup_task.sh)
- sakila.customer_audit_log table created (empty, ready for trigger inserts)
- sakila.customer_loyalty table created (empty, ready for procedure inserts)
- No tr_customer_audit trigger exists
- No sp_calculate_loyalty_tiers procedure exists
- No export CSV exists

## Data Source
Sakila sample database — 599 customers, 16,044 rentals. Real DVD rental store data.
All trigger testing uses real customer records from the Sakila DB.

## Difficulty: hard
Agent is told:
- Exact trigger name, table, timing, event (AFTER UPDATE on customer)
- Exact procedure name and tier logic (Bronze/Silver/Gold boundaries)
- What columns to log in the audit table
- What columns to populate in the loyalty table
Agent must determine:
- Correct MySQL TRIGGER syntax with OLD and NEW record references
- Correct DELIMITER and PROCEDURE syntax
- How to navigate MySQL Workbench's trigger/procedure editors
- Which customers to UPDATE for testing (any 5+ will do)

## Scoring (100 points)
- tr_customer_audit AFTER UPDATE trigger created: 25 pts
- sp_calculate_loyalty_tiers procedure created: 20 pts
- audit_log has >= 5 entries from >= 5 distinct customers with email data: 20 pts
- customer_loyalty has >= 500 rows with all 3 tiers present: 25 pts
- CSV export with >= 500 loyalty rows: 10 pts
**Pass threshold: 60 points**

## Verification Strategy
- Checks information_schema.TRIGGERS for trigger name, timing, event
- Checks information_schema.ROUTINES for procedure
- Counts customer_audit_log rows and distinct customer_ids
- Counts customer_loyalty rows and tier distribution
- Checks CSV file existence, row count, and modification timestamp

## Feature Coverage
- Trigger Editor (CREATE TRIGGER with OLD/NEW references)
- Stored Procedure Editor (CREATE PROCEDURE with DELIMITER)
- SQL Query Editor (UPDATE statements to test trigger, CALL statement)
- Schema browser (understanding Sakila customer and rental relationships)
- Data Export (CSV from customer_loyalty table)

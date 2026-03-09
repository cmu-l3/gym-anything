# Task: sakila_performance_optimization

## Domain Context
Computer Systems Analysts and Database Administrators routinely investigate query performance
issues in production databases. A common culprit is missing indexes — which can happen after
failed migrations, accidental DROP INDEX commands, or schema refactors. This task simulates
a real DBA scenario where three critical indexes have been removed from the Sakila database,
causing query plans to degrade to full table scans.

## Occupation Context
Primary occupations: Computer Systems Analysts ($1B GDP), Database Administrators ($668M GDP)
Rationale: "Analysts frequently query databases to understand legacy data structures, validate
migrations, and design new schemas." — master_dataset.csv

## Task Goal
The agent must:
1. Use EXPLAIN in MySQL Workbench to diagnose missing indexes on rental, payment, and inventory tables
2. Restore all three missing indexes
3. Create view v_monthly_revenue (columns: payment_year, payment_month, total_revenue)
4. Create stored procedure sp_monthly_revenue(p_year INT)
5. Call sp_monthly_revenue(2005) and export to /home/ga/Documents/exports/monthly_revenue_2005.csv

## Starting State (set up by setup_task.sh)
- idx_fk_customer_id dropped from sakila.rental
- idx_fk_rental_id dropped from sakila.payment
- idx_fk_film_id dropped from sakila.inventory
- No v_monthly_revenue view exists
- No sp_monthly_revenue procedure exists

## Data Source
Sakila sample database — official MySQL sample database (real DVD rental store data).
https://dev.mysql.com/doc/sakila/en/

## Difficulty: hard
Agent is told which tables have issues (rental, payment, inventory) but must:
- Discover specifically which columns/indexes are missing via EXPLAIN
- Determine the correct index definitions
- Write correct SQL for the view and procedure
- Navigate MySQL Workbench to create triggers and procedures

## Scoring (100 points)
- rental.customer_id index restored: 20 pts
- payment.rental_id index restored: 20 pts
- inventory.film_id index restored: 10 pts
- v_monthly_revenue view created with correct columns: 20 pts
- sp_monthly_revenue procedure created: 20 pts
- CSV export (/home/ga/Documents/exports/monthly_revenue_2005.csv) with >= 12 rows: 10 pts
**Pass threshold: 60 points**

## Verification Strategy
- Checks information_schema.STATISTICS for restored indexes
- Checks information_schema.VIEWS for v_monthly_revenue
- Checks information_schema.ROUTINES for sp_monthly_revenue
- Checks CSV file existence, row count, and modification timestamp vs task start

## Feature Coverage
- SQL Query Editor (EXPLAIN, CREATE VIEW, CREATE PROCEDURE)
- Table Editor / Index management
- Schema browser (examining table structure)
- Data Export (CSV from procedure results)

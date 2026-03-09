# Task: sakila_bi_analytics

## Domain Context
Business Intelligence Analysts regularly build reporting layers on transactional databases:
they create views that join multiple fact/dimension tables, set up read-only reporting users,
grant appropriate permissions, and export data for downstream tools. This task requires all
four of these professional workflows chained together.

## Occupation Context
Primary occupation: Business Intelligence Analysts ($1.3B GDP)
Rationale: "Analysts frequently query data warehouses and databases using SQL clients to
retrieve data for analysis." — master_dataset.csv

## Task Goal
1. Create v_film_revenue_by_store (film + inventory + store + rental + payment join)
2. Create v_customer_lifetime_value (customer + rental + payment aggregation)
3. Create MySQL user 'reporter'@'localhost' with password 'Report2024!'
4. Grant SELECT on both views to reporter
5. Export v_customer_lifetime_value to /home/ga/Documents/exports/customer_lifetime_value.csv

## Starting State (set up by setup_task.sh)
- Sakila database unchanged (complete, real data)
- No v_film_revenue_by_store view
- No v_customer_lifetime_value view
- No 'reporter'@'localhost' user
- Target output CSV does not exist

## Data Source
Sakila sample database — official MySQL sample database.
Contains 599 customers, 1000 films, 2 stores, 16,044 rentals, 14,596 payments.

## Difficulty: hard
Agent is told:
- Exactly what to create (view names, user name/password, required columns)
- Where to export the CSV
Agent must determine:
- The correct multi-table JOIN queries for each view
- How to create a user and grant privileges in MySQL Workbench
- How to navigate to Views, User Admin, and Export in MySQL Workbench

## Scoring (100 points)
- v_film_revenue_by_store with film_id, store_id, rental_count, total_revenue cols: 20 pts
- v_customer_lifetime_value with customer_id, name, total_spent cols + >= 500 rows: 20 pts
- reporter@localhost user created: 20 pts
- reporter has SELECT on v_film_revenue_by_store: 15 pts
- reporter has SELECT on v_customer_lifetime_value: 15 pts
- CSV export with >= 500 customer rows: 10 pts
**Pass threshold: 60 points**

## Verification Strategy
- Checks information_schema.VIEWS for both views and their column names
- Checks mysql.user for reporter user existence
- Checks information_schema.TABLE_PRIVILEGES (and SCHEMA_PRIVILEGES) for grants
- Checks CSV file existence, row count, and modification timestamp

## Feature Coverage
- SQL Query Editor (CREATE VIEW with multi-table JOINs)
- User Administration panel (create user, set password)
- Schema Privileges / Grant management
- Data Export (CSV from view)
- Schema browser (understanding Sakila table relationships)

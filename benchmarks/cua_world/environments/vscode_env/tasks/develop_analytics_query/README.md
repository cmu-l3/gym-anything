# Develop Analytics Query Task

**Difficulty**: 🟡 Medium  
**Skills**: SQL query development, database exploration, query optimization  
**Duration**: 600 seconds (10 minutes)  
**Steps**: ~50

## Objective

Write a complex SQL query to answer a business question: "What are the top 5 products by revenue for each region in Q4 2024, including the customer count for each product?"

## Scenario

You're a data analyst working on a quarterly sales report. The finance team needs sales analytics, but the database schema is only partially documented. You must explore the schema, write the query, test it, and verify results match expected output.

## Database Schema

SQLite database (`sales.db`) with three tables:
- **products**: (id, name, category, price)
- **sales**: (id, product_id, customer_id, region, quantity, sale_date)
- **customers**: (id, name, email, region)

**Data quirks**: Some sales records have NULL regions (data quality issue from legacy system).

## Expected Workflow

1. Open workspace in VSCode
2. Explore `schema_notes.md` for partial documentation
3. Open `sales.db` or write SQL queries to explore schema
4. Create `query_solution.sql` file
5. Write SQL query with:
   - JOINs across products and sales tables
   - GROUP BY for aggregation
   - Window functions (RANK) for ranking
   - Filter Q4 2024 dates (2024-10-01 to 2024-12-31)
   - Filter out NULL regions
6. Add SQL comments documenting the query
7. Test query by running it (optional)
8. Save the file

## Expected Output Format

Your query should return columns:
- region (text)
- product_name (text)
- total_revenue (numeric)
- customer_count (integer)
- rank (integer)

Top 5 products per region, ordered by region then rank.

## Verification

Checks for:
1. File `query_solution.sql` exists
2. Query is executable SQL
3. Query includes documentation comments
4. Query uses JOINs and GROUP BY
5. Query results match expected output
6. Query is performant (< 0.5s)

**Pass Threshold**: 100% (all criteria must pass for correct output)
# Optimize Database Query Task

**Difficulty**: 🟡 Medium  
**Skills**: SQL query writing, file creation, code formatting, database optimization  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Create an optimized SQL query file to replace a slow N+1 query pattern with an efficient JOIN-based query. The query should retrieve product sales data aggregated by category for an analytics dashboard.

## Scenario

You're investigating performance issues in the analytics dashboard. The "Top Products by Category" report times out after 30 seconds. You need to create a properly formatted SQL file with an optimized query.

## Expected Workflow

1. Review the schema reference file (`schema.txt`) and README in the workspace
2. Create a new file: `top_products_by_category.sql`
3. Write a SQL query that:
   - Joins orders → order_items → products → categories
   - Aggregates sales data (SUM, COUNT)
   - Groups by category and product
   - Orders by total revenue (DESC)
   - Limits to top 100 results
4. Format with proper SQL conventions (uppercase keywords, indentation)
5. Add at least one comment explaining the query
6. Save the file

## Verification

Checks for:
1. File exists at correct location
2. Contains proper SQL structure (SELECT, JOIN, GROUP BY, ORDER BY, LIMIT)
3. At least 3 JOIN clauses present
4. Aggregate functions used (SUM/COUNT)
5. References correct tables (orders, order_items, products, categories)
6. SQL keywords in uppercase
7. Multi-line formatting with indentation
8. At least one comment (-- or /* */)

**Pass Threshold**: 85% (11/13 criteria)
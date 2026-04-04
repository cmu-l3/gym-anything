# Generate Mock Data Task

**Difficulty**: 🟡 Medium  
**Skills**: Code generation, data modeling, TypeScript/JavaScript, domain knowledge  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

Create a TypeScript or JavaScript file that generates realistic mock data for an e-commerce application. The mock data generator must produce internally-consistent test data with proper relationships between entities (users, products, orders).

## Context

You're a backend developer who needs to test the checkout flow logic but can't use production customer data due to privacy concerns. The mock data must be realistic enough to catch edge cases (international shipping, promo codes, tax calculations) while maintaining referential integrity (order totals must equal sum of items plus shipping minus discounts).

## Requirements

Your mock data generator must include:

### 1. Entity Types (Required)
- **Users/Customers**: with names, emails, and addresses
- **Products**: with names, SKUs, prices, and categories
- **Orders**: with user references, order items, and calculated totals

### 2. Referential Integrity
- Orders must reference valid user IDs
- Order items must reference valid product IDs
- All IDs must be consistent across entities

### 3. Calculations
- Order totals must be calculated correctly
- Include: subtotal (sum of items), shipping, tax, total
- Optionally include discounts/promo codes

### 4. Edge Cases
Include variety to catch edge cases:
- International addresses (different countries)
- Various order sizes (1 item, bulk orders)
- Multiple currencies or price ranges
- Different product categories

### 5. Code Structure
- Organize code into multiple functions
- Use helper functions for generating each entity type
- Consider using deterministic random generation (seeding) for reproducibility

## Expected File Structure

Create a file named `mockDataGenerator.ts` (TypeScript) or `mockDataGenerator.js` (JavaScript) with this general structure:

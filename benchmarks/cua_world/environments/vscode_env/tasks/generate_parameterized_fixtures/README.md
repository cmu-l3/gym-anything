# Generate Parameterized Fixtures Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-cursor editing, find/replace, JSON manipulation, efficient workflows  
**Duration**: 360 seconds (6 minutes)  
**Steps**: ~50

## Objective

Generate 20 realistic user profile fixtures for testing an e-commerce system. Starting from a single user template, create variations using efficient VSCode editing techniques (multi-cursor, find/replace, snippets).

## Scenario

You're building integration tests for an e-commerce checkout system. You need diverse user profiles with different characteristics (billing addresses, order histories, payment methods, membership tiers). Manually duplicating and editing is tedious and error-prone.

## Requirements

Create `/home/ga/workspace/test_fixtures/users_fixture.json` with:

- **20 user objects** in a JSON array
- **Unique user IDs**: Sequential 1001-1020
- **Unique emails**: Format `firstname.lastname@example.com`, all different
- **Name diversity**: At least 15 distinct first names
- **Age range**: 18-65 years
- **Membership distribution**: ~8 bronze, ~7 silver, ~5 gold (±1 tolerance)
- **City variety**: At least 4 different cities from: New York, London, Tokyo, Berlin, Toronto, Sydney
- **Date spread**: Registration dates across at least 6 different months in 2023-2024
- **Account balance**: $0-$500 range

## Expected Workflow

1. Review template_user.json and requirements.txt
2. Duplicate the template 20 times into an array structure
3. Use multi-cursor editing to update user IDs (1001-1020)
4. Systematically vary names, emails, ages, tiers, cities, dates, balances
5. Save as users_fixture.json
6. Verify JSON syntax is valid

## Verification

Checks for:
1. Correct user count (20)
2. Unique sequential user IDs (1001-1020)
3. Unique, valid email formats
4. Name diversity (15+ unique first names)
5. Age constraints (18-65)
6. Membership tier distribution
7. City variety (4+ cities)
8. Date spread (6+ months)
9. Balance range ($0-$500)

**Pass Threshold**: 85% (score ≥ 85/100)
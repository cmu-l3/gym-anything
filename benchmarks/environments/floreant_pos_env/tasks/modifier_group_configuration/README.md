# Task: Modifier Group Configuration

## Overview
**Role**: Restaurant Manager
**Difficulty**: Very Hard
**Domain**: Restaurant POS Customization / Modifier Configuration

## Business Context
Customer satisfaction surveys revealed that guests want more customization options when ordering pizza and burgers. The manager must configure the POS with two modifier groups that allow servers to record customer add-on requests and charge accordingly.

## Task Requirements

### Modifier Group 1: PIZZA TOPPINGS
Create a modifier group called **PIZZA TOPPINGS** with exactly eight modifiers:

| Modifier | Price |
|----------|-------|
| EXTRA CHEESE | $1.50 |
| MUSHROOMS | $0.75 |
| PEPPERONI | $1.25 |
| ONIONS | $0.50 |
| PEPPERS | $0.75 |
| OLIVES | $0.50 |
| ANCHOVIES | $0.75 |
| SAUSAGE | $1.25 |

### Modifier Group 2: BURGER ADD-ONS
Create a modifier group called **BURGER ADD-ONS** with five modifiers:

| Modifier | Price |
|----------|-------|
| AVOCADO | $1.50 |
| BACON | $1.25 |
| FRIED EGG | $1.00 |
| EXTRA PATTY | $3.00 |
| JALAPENOS | $0.50 |

### Assignment
Assign the **PIZZA TOPPINGS** modifier group to at least one item in the **PIZZA** menu category so it appears when that item is ordered.

## Why This Is Hard
- Modifier groups are in a different part of the Back Office than menu items and categories
- Must create 2 modifier groups with 13 total modifiers (13 separate add operations)
- Then must navigate to a pizza item and assign the modifier group to it
- The modifier assignment UI is separate from the modifier creation UI
- This exercises 3 distinct Back Office features across multiple navigation areas

## Scoring (100 points)
- PIZZA TOPPINGS group created: 15 pts
- Each of 8 pizza modifiers with correct name (4 pts each): 32 pts
- BURGER ADD-ONS group created: 15 pts
- Each of 5 burger modifiers with correct name (3 pts each): 15 pts
- PIZZA TOPPINGS assigned to ≥1 pizza item: 20 pts
- Correct prices on ≥10 of 13 modifiers: 3 pts bonus
- Pass threshold: 60 points

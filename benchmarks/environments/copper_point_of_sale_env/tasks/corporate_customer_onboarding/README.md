# Task: Corporate Customer Onboarding

**Difficulty:** Very Hard
**Timeout:** 720 seconds | **Max Steps:** 90
**Environment:** Copper Point of Sale (Windows 11)

## Scenario

You are the B2B sales manager setting up corporate wholesale accounts. The store is expanding into business-to-business sales and you must onboard 6 new corporate clients with tiered pricing, while also updating the loyalty status of 3 existing retail customers. Files on the Desktop provide the necessary data.

## Required Actions

1. **Import existing customers**: Load `C:\Users\Docker\Desktop\existing_customers.csv` (30 retail customers) into Copper's Customer database.

2. **Add 6 new corporate clients** from `C:\Users\Docker\Desktop\corporate_accounts.txt`, setting Company, Contact, Email, Phone, Address, and Notes (tier + credit limit) for each:

   | Company | Tier | Credit Limit |
   |---------|------|-------------|
   | Pacific Northwest Distributors | GOLD | $25,000 |
   | Midwest Retail Holdings | SILVER | $15,000 |
   | Southern Fashion Group | GOLD | $30,000 |
   | Great Lakes Supply Co. | BRONZE | $5,000 |
   | Atlantic Coast Trading | SILVER | $12,000 |
   | Mountain West Goods | BRONZE | $7,500 |

3. **Update 3 existing customers' Notes**:
   - **Sheryl Baxter**: add `Preferred Account: Yes`
   - **Preston Lozano**: add `Preferred Account: Yes`
   - **Roy Berry**: add `Preferred Account: No, Past Due Balance`

4. **Export customer list**: Export to `C:\Users\Docker\Desktop\customer_accounts.csv`.

## Scoring (100 pts)

| Criterion | Points |
|-----------|--------|
| customer_accounts.csv exists and is new | 15 |
| Total rows ≥ 36 (30 existing + 6 new) | 15 |
| Each corporate company in export (×6) | 5 pts each = 30 |
| Each existing customer updated (×3) | 5 pts each = 15 |
| GOLD tier present | 5 |
| SILVER tier present | 5 |
| BRONZE tier present | 5 |
| Credit limit info present | 10 |
| **Total** | **100** |

**Pass threshold:** ≥ 60 points
**Gate:** Export file must exist and be newer than task start timestamp.

## Verification Output

The export script writes `C:\Users\Docker\corporate_onboarding_result.json` with detected company names, tier information, credit limit evidence, and customer update status.

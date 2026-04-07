# Task: crypto_day_trader_return

## Domain Context

Cryptocurrency taxation is one of the fastest-growing complexity areas for Canadian accountants and tax preparers. The CRA treats cryptocurrency as a commodity; dispositions trigger capital gain or loss events. Multiple transactions require per-disposition Adjusted Cost Base (ACB) tracking on Schedule 3. The superficial loss rule (Income Tax Act s.54) is a critical and commonly-missed rule: if a taxpayer sells a security at a loss and repurchases the same or identical property within 30 days before or after the sale, the loss is DENIED for that year and added to the ACB of the repurchased property.

Additionally, staking rewards and interest earned on cryptocurrency platforms are treated as income (not capital gains) in the year received, requiring a T5 entry. This task also involves T777 home office expenses and RRSP contributions — features that must all be correctly entered for a complete return.

**Occupation relevance**: Accountants and Auditors (O*NET 13-2011.00; importance=86) frequently handle cryptocurrency clients. The CRA's cryptocurrency audit initiative since 2021 has made this a high-priority compliance area.

## Goal

Complete Priya Nair's 2024 Canadian personal income tax return using StudioTax 2024. Save the completed return as `priya_nair.24t` in `C:\Users\Docker\Documents\StudioTax\`.

Tax documents are in: `C:\Users\Docker\Desktop\TaxDocuments\nair\`

## What Success Looks Like

The saved `.24t` return file must contain:
- Priya Nair as the taxpayer (BC resident, single)
- T4 employment income from Shopify Inc. ($72,500)
- T5 interest income from cryptocurrency staking rewards ($1,840) — entered as interest, NOT capital gain
- Capital gains on Schedule 3 from multiple cryptocurrency dispositions (ETH and BTC gains; MATIC loss correctly deducted; SOL superficial loss NOT deducted)
- Net taxable capital gain of $11,900 (50% inclusion = $5,950)
- RRSP contribution ($5,500) deducted
- File saved with timestamp after task start

## Application Features Required

This task exercises at least 5 distinct StudioTax features:
1. **T4 slip entry** — employment income with all boxes
2. **T5 slip entry** — interest income (staking rewards)
3. **Schedule 3 capital gains** — multiple disposition entries (ETH, BTC, MATIC; SOL excluded)
4. **Schedule 7 RRSP** — RRSP contribution deduction
5. **T777 employment expenses** — home office deduction (detailed method)
6. **British Columbia province** — BC-specific provincial calculations

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| File saved with correct name | 15 | `priya_nair.24t` exists and > 500 bytes |
| Timestamp valid | 10 | File modified after task start |
| Taxpayer name present | 10 | "Nair" + "Priya" in file |
| T4 employment income $72,500 | 15 | String "72500" found |
| T5 staking/interest $1,840 | 10 | String "1840" found |
| Capital gains (ETH $7,600 and/or BTC $6,400) | 15 | "7600" and/or "6400" found |
| RRSP $5,500 | 10 | String "5500" found |
| MATIC loss + home office entries | 15 | "2100" and/or "2288"/"2202" found |
| **VLM evaluation** | 25 | Reserved |
| **Total** | **115** | Pass threshold: 60/100 programmatic |

**Score cap**: If T4 employment income ($72,500) is not present, score capped at 55. This ensures the core employment return is completed.

## Critical Complexity

- **Superficial loss rule**: The SOL (Solana) transaction on Nov 25 at a loss of $980 was followed by a repurchase on Dec 8 (13 days later) — this is WITHIN 30 days. The $980 loss is DENIED under ITA s.54 and must NOT appear on Schedule 3. An agent that enters all 4 transactions will over-report capital losses.
- **Staking as income, not capital gain**: The $1,840 from crypto.com is a T5 interest amount (Line 12100), not a Schedule 3 capital gain. Many taxpayers and some agents incorrectly treat staking as capital gain.
- **Multiple Schedule 3 entries**: The agent must enter ETH, BTC, and MATIC separately (3 dispositions) while knowing to skip the SOL entry entirely.
- **Home office (T777)**: Requires recognition that an employer-signed T2200S is needed and the deduction goes on Line 22900.

## Edge Cases

- Agent enters SOL loss ($980) — VLM evaluation will flag; programmatic score is not directly affected but the return is technically incorrect
- Agent treats staking rewards as capital gain instead of interest income — fails T5 criterion
- Agent misses MATIC loss entry — partial capital gains credit still given for ETH/BTC gains
- Agent skips home office — criterion 8 partially fails

## Source Data

- Scenario file: `C:\workspace\data\scenario_nair_crypto.txt`
- CRA capital gains guide: T4037 (Capital Gains) 2024
- Superficial loss rule: ITA s.54, CRA Interpretation Bulletin IT-387R2
- Company names: Real (Shopify Inc., Coinbase Canada Inc., Crypto.com / Foris DAX Inc.)
- Tax rates: Real 2024 CRA federal and BC provincial brackets

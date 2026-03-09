# Portfolio Performance Environment - Evidence Documentation

## Environment Overview
- **Application**: Portfolio Performance v0.81.5 (Eclipse RCP, Java)
- **Base Image**: ubuntu-gnome-systemd_highres (1920x1080)
- **Installation**: ~57 seconds (downloads tar.gz from GitHub, installs OpenJDK 21)
- **10 Tasks**: create_portfolio, record_buy_transaction, add_security_and_buy, import_historical_quotes, export_portfolio_csv, reconcile_brokerage_statement, record_quarterly_dividends, correct_erroneous_transactions, add_security_with_price_history, export_securities_transactions

## Verification Methodology

### Pipeline Simulation (Not Agent Runs)
The scores in `e2e_summary.json` are from **pipeline simulation** only:
1. Manually-crafted XML files simulate expected agent output (e.g., a saved portfolio with a BUY transaction)
2. `export_result.sh` scripts parse these XMLs and write JSON results
3. `verifier.py` scripts score the JSON results

These scores verify that the **export+verifier pipeline works correctly**, but do NOT represent actual CUA agent performance. Actual agent scores will depend on GUI interaction quality.

### Screenshots
- **Screenshots 01-12**: Manual walkthrough of the create_portfolio task wizard (creating a portfolio via PP's GUI)
- **Screenshots 13-15**: Verification that all 5 XML templates (trading_portfolio.xml, investment_portfolio.xml, growth_portfolio.xml, diversified_portfolio.xml) load correctly in PP v0.81.5 GUI
- **Screenshots 16-17**: Manual BUY dialog interaction testing (opening buy dialog, selecting security)

No final-state screenshots from actual agent runs are included yet.

### Pipeline Simulation Scores

#### Original 5 Tasks
| Task | Pipeline Score | Notes |
|------|---------------|-------|
| create_portfolio | 100/100 | Simulated output XML with correct structure |
| record_buy_transaction | 100/100 | Simulated crossEntry BUY format |
| add_security_and_buy | 95/100 | Simulated GOOGL security + BUY |
| import_historical_quotes | 100/100 | Simulated 125 AAPL price entries |
| export_portfolio_csv | 100/100 | Simulated CSV with Date/Type/Value columns |

#### New 5 Tasks (added 2026-02-25)
New tasks tested via `test_new_tasks_pipeline.py` using mock copy_from_env (no VM required).

| Task | Difficulty | Do-Nothing | Partial | Full | Pass |
|------|-----------|-----------|---------|------|------|
| reconcile_brokerage_statement | hard | 0/100 | 55/100 | 97/100 | ✓ |
| record_quarterly_dividends | hard | 0/100 | 55/100 | 100/100 | ✓ |
| correct_erroneous_transactions | very_hard | 0/100 | 55/100 | 100/100 | ✓ |
| add_security_with_price_history | hard | 0/100 | 60/100 | 100/100 | ✓ |
| export_securities_transactions | hard | 0/100 | 80/100 | 100/100 | ✓ |

See `<task_name>_evidence.json` for detailed test results per task.

## Key Technical Details

### PP XML Data Format (v0.81.5, version=68)
- **Prices**: stored in hecto units (v="18564" = $185.64)
- **Shares**: stored in nano units (10^9). 8000000000 = 8 shares
- **Amounts**: stored in hecto units. 10000000 = $100,000.00
- **Fees**: `<unit type="FEE"><amount currency="USD" amount="999"/></unit>` (999 = $9.99)
- **Security references**: `reference="../../../../securities/security"` (first), `[N]` (Nth, 1-indexed)

### crossEntry Format for BUY/SELL Transactions
PP v0.81.5 uses XStream `crossEntry class="buysell"` to serialize BUY/SELL:
- The real `<portfolio>` with transactions lives INSIDE `account-transaction/crossEntry/portfolio`
- `<portfolios>` section contains only `<portfolio reference="..."/>` pointing to the nested portfolio
- Security references from inside crossEntry go 9 levels up: `../../../../../../../../../securities/security[N]`
- Export scripts must use `root.iter("portfolio")` + `extend()` to accumulate transactions from all portfolio elements

### File Opening Approach
PP v0.81.5 ignores command-line file arguments (always shows Welcome page). Setup scripts use:
1. Launch PP without file argument
2. Wait for window
3. `Ctrl+O` > `Ctrl+L` > type path > `Enter` via `open_file_in_pp()` helper

### Bugs Fixed During Development
1. **`grep -c || echo "0"` doubles output**: grep -c prints "0" AND returns exit code 1, so `|| echo "0"` adds another "0". Fixed with `|| true`.
2. **`echo` trailing newlines**: `echo "$VAR" > file` writes trailing newline. Fixed with `printf '%s'`.
3. **`root.iter("security")` matches references**: Also matches `<security reference="..."/>` in transactions. Fixed with `root.find("securities").findall("security")`.
4. **Portfolio iteration overwrites**: `for portfolio in root.iter("portfolio")` finds both real and reference portfolios. The reference portfolio (last) has 0 txns, overwriting the real count. Fixed by accumulating with `extend()`.
5. **XML version mismatch**: Version 71 causes "Invalid XML Format" in v0.81.5. Must use version 68.
6. **count_securities_in_xml grep bug**: `grep -c "<security>"` also matches `<security reference="..."/>`. Fixed with Python XML parsing.

### CUA Coordinate Scaling
- ask_cua.py returns coordinates in 1280x720 space
- Scale to actual resolution: `actual_x = cua_x * 1920 / 1280`, `actual_y = cua_y * 1080 / 720`

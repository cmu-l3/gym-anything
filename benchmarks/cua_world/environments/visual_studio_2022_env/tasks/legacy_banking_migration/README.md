# Task: legacy_banking_migration

## Domain Context

**Primary occupation**: Software Developers (GDP $27.1B), Financial Quantitative Analysts (GDP $622M)

Meridian Bank's core transaction processing library (`BankingCore`) was originally written against .NET Framework 4.5 in 2012 and recently migrated to .NET 8. The migration was purely mechanical — no code patterns were updated. The library compiles and runs, but uses deprecated APIs that:

1. Cause undetectable type errors at runtime (non-generic collections)
2. Introduce timezone bugs in transaction timestamps (DateTime.Now vs DateTimeOffset.UtcNow)
3. Use a predictable random number generator for transaction reference IDs (security risk)
4. Create O(n) string allocations in hot report-generation loops (performance incident under load)

A production incident in Q3 was traced back to an incorrect decimal cast from Hashtable — the bug would have been caught at compile time with generics.

## Task Description

The agent must open `TransactionProcessor.cs` (and related files) in the BankingCore project, identify all deprecated patterns, and modernize them to current .NET 8 standards. The solution must build with 0 errors after changes.

**The agent is NOT told which specific lines are wrong — it must read the code and apply domain knowledge about .NET best practices.**

## Success Criteria

| Criterion | Points | What to check |
|-----------|--------|---------------|
| Replace `ArrayList` with `List<Transaction>` | 25 | `ArrayList` absent from TransactionProcessor.cs |
| Replace `Hashtable` with `Dictionary<string, decimal>` | 25 | `Hashtable` absent from TransactionProcessor.cs |
| Replace `DateTime.Now` with `DateTimeOffset.UtcNow` | 20 | `DateTime.Now` absent from project files |
| Replace `new Random()` with `RandomNumberGenerator` | 15 | `new Random(` absent; secure RNG present |
| Use `StringBuilder` in `GenerateReport()` | 15 | `StringBuilder` present in TransactionProcessor.cs |

**Pass threshold**: 60 points
**Build gate**: If build has errors, score is capped at 40

## Starting Code Issues (Ground Truth — for verifier use)

In `TransactionProcessor.cs`:
- Line ~6: `private ArrayList _transactions = new ArrayList();`
- Line ~7: `private Hashtable _balances = new Hashtable();`
- Line ~8: `private static Random _rng = new Random();`
- Line ~14: uses `_rng.Next(...)` for transaction IDs
- Line ~20: `tx.Timestamp = DateTime.Now;`
- Line ~25: `System.Threading.Thread.Sleep(200);`
- Line ~40: `GenerateReport()` uses string concatenation in a foreach loop

## Verification Strategy

`export_result.ps1`:
1. Kills VS to ensure files are flushed
2. Reads `TransactionProcessor.cs` content
3. Regex-checks for each anti-pattern (absent/present)
4. Runs `dotnet build` and captures error count
5. Writes result JSON to `C:\Users\Docker\legacy_banking_migration_result.json`

`verifier.py`:
1. Copies result JSON from VM
2. Also independently copies TransactionProcessor.cs and checks source
3. Scores each criterion independently
4. Applies build gate

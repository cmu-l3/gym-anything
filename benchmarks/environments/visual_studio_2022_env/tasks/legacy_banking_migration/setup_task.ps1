# Setup script for legacy_banking_migration task.
# Creates the BankingCore .NET 8 project with deliberately legacy patterns that
# the agent must identify and modernize.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_setup_legacy_banking_migration.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up legacy_banking_migration ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) { . $utils } else { Write-Host "WARNING: task_utils.ps1 not found" }

    # Kill any running VS first
    if (Get-Command Kill-AllVS2022 -ErrorAction SilentlyContinue) {
        Kill-AllVS2022
    } else {
        Get-Process devenv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }

    $dotnetExe = "C:\Program Files\dotnet\dotnet.exe"
    if (-not (Test-Path $dotnetExe)) {
        $dc = Get-Command dotnet -ErrorAction SilentlyContinue
        if ($dc) { $dotnetExe = $dc.Source } else { throw "dotnet.exe not found" }
    }

    $projectsRoot = "C:\Users\Docker\source\repos"
    New-Item -ItemType Directory -Force -Path $projectsRoot | Out-Null

    $projDir = "$projectsRoot\BankingCore"
    New-Item -ItemType Directory -Force -Path $projDir | Out-Null

    # Write .csproj
    $csprojContent = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>disable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <RootNamespace>BankingCore</RootNamespace>
  </PropertyGroup>
</Project>
'@
    [System.IO.File]::WriteAllText("$projDir\BankingCore.csproj", $csprojContent)

    # Write Transaction.cs — a simple data class (no bugs here)
    $transactionCs = @'
using System;

namespace BankingCore
{
    /// <summary>
    /// Represents a single financial transaction.
    /// </summary>
    public class Transaction
    {
        public string TransactionId { get; set; }
        public DateTime Timestamp { get; set; }
        public string AccountNumber { get; set; }
        public decimal Amount { get; set; }
        public string Currency { get; set; }

        /// <summary>Type: "CREDIT" or "DEBIT"</summary>
        public string Type { get; set; }

        public Transaction(string id, string accountNumber, decimal amount,
                           string currency, string type)
        {
            TransactionId = id;
            AccountNumber = accountNumber;
            Amount = amount;
            Currency = currency;
            Type = type;
        }
    }
}
'@
    [System.IO.File]::WriteAllText("$projDir\Transaction.cs", $transactionCs)

    # Write TransactionProcessor.cs — the file with all the legacy anti-patterns
    # This is the file the agent must modernize.
    $processorCs = @'
using System;
using System.Collections;   // Legacy: ArrayList, Hashtable
using System.Threading;     // Legacy: Thread.Sleep

namespace BankingCore
{
    /// <summary>
    /// Core transaction processor for Meridian Bank.
    /// Originally written for .NET Framework 4.5; migrated to .NET 8 mechanically.
    /// </summary>
    public class TransactionProcessor
    {
        // LEGACY: non-generic collection; runtime casts required
        private ArrayList _transactions = new ArrayList();

        // LEGACY: non-generic hashtable; decimal values require explicit cast
        private Hashtable _balances = new Hashtable();

        // LEGACY: System.Random is not cryptographically secure
        private static Random _rng = new Random();

        /// <summary>
        /// Generates a transaction reference ID.
        /// </summary>
        public string GenerateTransactionId()
        {
            // LEGACY: predictable; should use cryptographic random source
            return "TXN-" + _rng.Next(1000000, 9999999).ToString();
        }

        /// <summary>
        /// Submits a transaction for processing.
        /// </summary>
        public void Submit(Transaction tx)
        {
            // LEGACY: DateTime.Now uses local timezone — causes audit log discrepancies
            tx.Timestamp = DateTime.Now;
            _transactions.Add(tx);
        }

        /// <summary>
        /// Processes all pending transactions and updates account balances.
        /// </summary>
        public void ProcessBatch()
        {
            // LEGACY: Thread.Sleep blocks the calling thread unnecessarily
            Thread.Sleep(200);

            foreach (Transaction tx in _transactions)
            {
                string acct = tx.AccountNumber;
                if (!_balances.ContainsKey(acct))
                    _balances[acct] = 0m;

                // LEGACY: explicit casts required because Hashtable stores object
                if (tx.Type == "CREDIT")
                    _balances[acct] = (decimal)_balances[acct] + tx.Amount;
                else
                    _balances[acct] = (decimal)_balances[acct] - tx.Amount;
            }
            _transactions.Clear();
        }

        /// <summary>
        /// Generates a formatted transaction report.
        /// </summary>
        public string GenerateReport()
        {
            // LEGACY: string concatenation inside loop creates O(n) allocations
            string report = "";
            report += "=== MERIDIAN BANK - TRANSACTION REPORT ===\r\n";
            report += "Date: " + DateTime.UtcNow.ToString("o") + "\r\n";
            report += "-------------------------------------------\r\n";
            foreach (Transaction tx in _transactions)
            {
                report += "[" + tx.TransactionId + "] ";
                report += tx.Timestamp.ToString("o") + " ";
                report += tx.AccountNumber + " ";
                report += tx.Type + " ";
                report += tx.Amount.ToString("F2") + " ";
                report += tx.Currency + "\r\n";
            }
            report += "-------------------------------------------\r\n";
            return report;
        }

        /// <summary>
        /// Returns the current balance for the specified account.
        /// </summary>
        public decimal GetBalance(string accountNumber)
        {
            if (_balances.ContainsKey(accountNumber))
                return (decimal)_balances[accountNumber];
            return 0m;
        }
    }
}
'@
    [System.IO.File]::WriteAllText("$projDir\TransactionProcessor.cs", $processorCs)

    # Write Program.cs — entry point; agent should NOT need to touch this
    $programCs = @'
using System;
using BankingCore;

var processor = new TransactionProcessor();

var tx1 = new Transaction(processor.GenerateTransactionId(), "ACC-001-MER", 15000.00m, "USD", "CREDIT");
var tx2 = new Transaction(processor.GenerateTransactionId(), "ACC-002-MER",  3250.75m, "USD", "DEBIT");
var tx3 = new Transaction(processor.GenerateTransactionId(), "ACC-001-MER",  1800.00m, "USD", "DEBIT");

processor.Submit(tx1);
processor.Submit(tx2);
processor.Submit(tx3);

Console.WriteLine(processor.GenerateReport());
processor.ProcessBatch();

Console.WriteLine($"Balance ACC-001-MER: {processor.GetBalance("ACC-001-MER"):C}");
Console.WriteLine($"Balance ACC-002-MER: {processor.GetBalance("ACC-002-MER"):C}");
'@
    [System.IO.File]::WriteAllText("$projDir\Program.cs", $programCs)

    Write-Host "BankingCore source files written."

    # Build once to verify it compiles with legacy patterns intact
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    & $dotnetExe build $projDir --nologo 2>&1 | ForEach-Object { Write-Host "  BUILD: $_" }
    if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: Initial BankingCore build failed — check source." }
    else { Write-Host "BankingCore initial build succeeded (legacy patterns compile)." }
    $ErrorActionPreference = $prevEAP

    # Clean build output so agent starts fresh
    Remove-Item "$projDir\bin" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$projDir\obj" -Recurse -Force -ErrorAction SilentlyContinue

    # Create .sln
    $slnPath = "$projDir\BankingCore.sln"
    if (-not (Test-Path $slnPath)) {
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        & $dotnetExe new sln -n BankingCore -o $projDir --force 2>&1 | Out-Null
        & $dotnetExe sln $slnPath add "$projDir\BankingCore.csproj" 2>&1 | Out-Null
        $ErrorActionPreference = $prevEAP
    }

    # Sleep 2 seconds THEN record timestamp — ensures source files have mtime < task_start
    Start-Sleep -Seconds 2
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_legacy_banking_migration.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp recorded: $ts"

    # Launch VS with the solution
    $devenvExe = $null
    if (Get-Command Find-VS2022Exe -ErrorAction SilentlyContinue) {
        $devenvExe = Find-VS2022Exe
    } else {
        $devenvExe = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"
    }

    if (Test-Path $devenvExe) {
        Write-Host "Launching VS with BankingCore.sln..."
        if (Get-Command Launch-VS2022Interactive -ErrorAction SilentlyContinue) {
            Launch-VS2022Interactive -DevenvExe $devenvExe -SolutionPath $slnPath -WaitSeconds 25
        } else {
            $launchScript = "C:\Windows\Temp\launch_banking.cmd"
            "@echo off`r`nstart `"`" `"$devenvExe`" /nosplash `"$slnPath`"" | Out-File $launchScript -Encoding ASCII
            $taskName = "LaunchVS_Banking"
            schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>$null | Out-Null
            schtasks /Run /TN $taskName 2>$null | Out-Null
            Start-Sleep -Seconds 25
            schtasks /Delete /TN $taskName /F 2>$null | Out-Null
        }

        if (Get-Command Dismiss-VSDialogsBestEffort -ErrorAction SilentlyContinue) {
            try { Dismiss-VSDialogsBestEffort -Retries 3 -InitialWaitSeconds 5 -BetweenRetriesSeconds 2 }
            catch { Write-Host "WARNING: Dialog dismissal: $($_.Exception.Message)" }
        }
    } else {
        Write-Host "WARNING: VS not found at expected path."
    }

    Write-Host "=== legacy_banking_migration setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}

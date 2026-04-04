# Task: JaCoCo Coverage Enforcement

## Overview

**Difficulty**: Very Hard
**Domain**: QA Engineering / Test Coverage
**Application**: Eclipse IDE with Maven Java project

A QA engineer must introduce test coverage infrastructure for an untested fintech transaction service and achieve ≥70% line coverage using JUnit 5 and Mockito.

## Goal

Starting from a codebase with zero test coverage, the agent must:

1. **Configure JaCoCo** — Add the `jacoco-maven-plugin` to `pom.xml` to:
   - Generate an HTML coverage report during the Maven `test` phase
   - Optionally enforce a minimum coverage threshold (70%)

2. **Write JUnit 5 + Mockito tests** covering:
   - `TransactionService`: `deposit()`, `withdraw()`, `transfer()`, `reverse()`, and error paths
   - `FeeCalculator`: all account types (CHECKING, SAVINGS) and transaction types (TRANSFER, WITHDRAWAL, DEPOSIT)
   - `TransactionValidator`: valid transactions, invalid amounts, inactive accounts, insufficient balance, transfer limit

3. **Achieve ≥70% line coverage** across the main service classes

## Success Criteria

- JaCoCo plugin declared in `pom.xml`
- At least 3 test files created
- Mockito annotations or `Mockito.mock()` present in tests
- JaCoCo HTML report generated at `target/site/jacoco/index.html`
- JaCoCo XML report at `target/site/jacoco/jacoco.xml` shows ≥70% line coverage
- `mvn clean test` passes

## Verification Strategy

1. JaCoCo plugin in pom.xml (15 pts)
2. Test files ≥ 3 (15 pts)
3. Mockito usage in tests (20 pts)
4. JaCoCo HTML report exists (20 pts)
5. Line coverage ≥ 70% (30 pts)

Pass threshold: 70/100

## Architecture Reference

The project uses interface-based repositories (`TransactionRepository`, `AccountRepository`) that must be mocked in tests. `TransactionService` depends on both repositories plus `FeeCalculator` and `TransactionValidator`. All business logic is in `TransactionService`, `FeeCalculator`, and `TransactionValidator`.

### JaCoCo Plugin Template

```xml
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <version>0.8.10</version>
  <executions>
    <execution>
      <goals><goal>prepare-agent</goal></goals>
    </execution>
    <execution>
      <id>report</id>
      <phase>test</phase>
      <goals><goal>report</goal></goals>
    </execution>
  </executions>
</plugin>
```

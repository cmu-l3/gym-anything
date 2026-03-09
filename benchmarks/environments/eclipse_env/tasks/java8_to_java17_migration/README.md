# Task: Java 8 to Java 17 Migration

## Overview

**Difficulty**: Hard
**Domain**: Java Development / Modernisation
**Application**: Eclipse IDE with Maven Java project

A Java developer must modernise a legacy HR system by replacing outdated Java 8 API usages with modern Java 17 equivalents.

## Goal

Update the `legacy-hr-system` project to Java 17 by replacing four categories of legacy code:

### 1. Date/Time API (java.util.Date → java.time)
- `Employee.java`: Replace `Date hireDate`, `Date dateOfBirth`, `Date lastModified` fields with `LocalDate`/`LocalDateTime`
- `PayrollCalculator.java`: Replace `Calendar`-based arithmetic with `Period.between()` and `ChronoUnit`
- `ReportGenerator.java`: Replace `new Date()` + `SimpleDateFormat` with `LocalDate.now()` + `DateTimeFormatter`
- `HrApplication.java`: Replace `Calendar.getInstance()` usage with `LocalDate` literals

### 2. Raw Types → Generics
- `EmployeeDirectory.java`: `Map employees` → `Map<Integer, Employee>`, `List` returns → `List<Employee>`
- `PayrollCalculator.java`: `List getAnnualBonusHistory()` → `List<Double>`, `List getLongServiceEmployees()` → `List<Employee>`
- `ReportGenerator.java`: `List employees` parameters → `List<Employee>`

### 3. StringBuffer → StringBuilder
- `EmployeeDirectory.java`: All `StringBuffer` → `StringBuilder`
- `ReportGenerator.java`: All `StringBuffer` → `StringBuilder`

### 4. Maven Compiler Version
- `pom.xml`: Change `maven.compiler.source` and `maven.compiler.target` from `8` to `17`

## Success Criteria

- No `java.util.Date` or `java.util.Calendar` imports in main source
- `java.time.*` classes used (LocalDate, Period, DateTimeFormatter)
- No raw type `List` or `Map` without generics
- No `StringBuffer` in main source (replaced with StringBuilder)
- `pom.xml` targets Java 17
- `mvn clean test` passes

## Verification Strategy

1. Date/Calendar removed from main source (25 pts)
2. java.time API used (20 pts)
3. Raw types replaced with generics (20 pts)
4. StringBuffer → StringBuilder (15 pts)
5. pom.xml targets Java 17 (10 pts)
6. Build + tests pass (10 pts)

Pass threshold: 65/100

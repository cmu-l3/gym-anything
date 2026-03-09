# Task: Multi-Module Maven Project Refactor

## Overview

**Difficulty**: Very Hard
**Domain**: Software Architecture
**Application**: Eclipse IDE with Maven Java project

A senior software architect must decompose an e-commerce monolith into a proper multi-module Maven structure, preserving all functionality and ensuring the project builds cleanly.

## Goal

Create a new multi-module Maven project at `/home/ga/ecommerce-refactored` with three child modules:

- **ecommerce-api**: Contains all model/domain classes (`Product`, `Customer`, `Order`, `OrderItem`)
- **ecommerce-persistence**: Contains all repository classes, declares dependency on `ecommerce-api`
- **ecommerce-service**: Contains all service classes, declares dependencies on both `ecommerce-api` and `ecommerce-persistence`

The parent POM must declare all three modules. Each child module must have its own `pom.xml`. Running `mvn clean install` from `/home/ga/ecommerce-refactored` must succeed.

## Success Criteria

- Parent POM exists at `/home/ga/ecommerce-refactored/pom.xml` with `<modules>` listing all 3 child modules
- Each of the 3 child modules has a `pom.xml` with `groupId=com.example`, `artifactId=ecommerce-{api,persistence,service}`, `version=1.0-SNAPSHOT`
- Model classes (`Product`, `Customer`, `Order`, `OrderItem`) exist in `ecommerce-api`
- Repository classes exist in `ecommerce-persistence`
- Service classes exist in `ecommerce-service`
- `ecommerce-persistence/pom.xml` declares dependency on `ecommerce-api`
- `ecommerce-service/pom.xml` declares dependency on both `ecommerce-api` and `ecommerce-persistence`
- `mvn clean install` runs from the parent directory and exits with code 0

## Verification Strategy

1. Parent POM contains `<modules>` with 3 modules listed (20 pts)
2. Each child module has a valid `pom.xml` (15 pts)
3. Model classes in ecommerce-api (15 pts)
4. Repository classes in ecommerce-persistence (15 pts)
5. Service classes in ecommerce-service (15 pts)
6. Inter-module dependencies declared correctly (10 pts)
7. Build passes with `mvn clean install` (10 pts)

Pass threshold: 70/100

## Source Project

The source monolith is at `/home/ga/ecommerce-monolith`. Do NOT modify the source project.

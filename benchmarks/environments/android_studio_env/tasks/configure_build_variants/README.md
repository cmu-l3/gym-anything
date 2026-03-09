# Task: configure_build_variants

## Overview
Configure proper build variants for the CalculatorApp to support different product tiers and deployment environments. This requires modifying the Gradle build configuration to add product flavors, build types, and flavor-specific resources.

## Domain Context
Configuring build variants is essential for professional Android development — apps typically need free/paid tiers, debug/staging/release environments, and different configurations per variant. This is a standard build engineering task.

## Goal
Set up the CalculatorApp with:
- Two product flavors: "free" and "premium" in a "tier" dimension
- A "staging" build type (in addition to default debug/release)
- Different applicationIdSuffix for each variant
- Flavor-specific string resources (different app_name per flavor)
- A signing config placeholder for release builds
- Project must sync and compile

## Success Criteria
- build.gradle.kts has flavorDimensions with "tier"
- build.gradle.kts has "free" and "premium" productFlavors
- build.gradle.kts has a "staging" buildType
- free flavor has applicationIdSuffix ".free"
- premium flavor has applicationIdSuffix ".premium"
- Flavor-specific res directories exist (app/src/free/res/, app/src/premium/res/)
- Each flavor has its own strings.xml with different app_name
- Project compiles (at least one variant)

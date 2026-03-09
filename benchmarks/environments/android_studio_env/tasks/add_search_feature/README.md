# Task: add_search_feature

## Overview
Add search and filtering functionality to the SunflowerApp so users can find plants by name, description, or grow zone. This requires changes across layout XML, string resources, a new utility class, and the main activity.

## Domain Context
Adding search functionality is a fundamental feature request in mobile development. It touches UI layout, business logic, and activity lifecycle — requiring coordination across multiple files and understanding of Android patterns.

## Goal
Implement a working search feature that filters the plant list as the user types. The search should match against plant name, description, and grow zone number.

## Success Criteria
- activity_main.xml has a SearchView or EditText for search input
- A PlantFilter.kt utility class exists with filter logic
- MainActivity.kt handles search text changes and filters the displayed list
- strings.xml has a search hint string resource
- Project compiles successfully

## Verification Strategy
Check each file for the required additions and verify compilation.

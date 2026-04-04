# Task: Migrate Database and Create Application Database

## Overview
BrightStar Media needs database infrastructure for a video catalog app. The agent must create a new database, grant cross-domain access to the existing Sakila sample database, create a properly structured table, and populate it with real genre data from the Sakila database.

## Domain Context
Web administrators regularly manage databases across hosted domains — creating app databases, granting cross-domain access, and setting up schema structures. This reflects a real scenario where a hosting client needs a new application database that also references shared data.

## Goal
1. Create brightstar_catalog database under brightstar.test
2. Grant brightstar.test MySQL user access to sakila
3. Create video_categories table with proper schema
4. Populate with 5+ real genre categories

## Why This Is Hard
- Requires using 3+ Virtualmin features: database creation, user grants, SQL execution
- Cross-domain database grants require understanding Virtualmin's MySQL user model
- Creating tables and inserting data requires finding the SQL interface (Webmin MySQL module or shell)
- The agent must reference the sakila.category table for real data
- Multiple independent subtasks with different verification criteria

## Verification Strategy
- Check brightstar_catalog database exists under brightstar.test
- Check brightstar user can access sakila
- Check video_categories table exists with correct columns
- Check at least 5 rows with real genre names
- Cross-reference inserted genres against Sakila's category table

## Edge Cases and Potential Issues
- Virtualmin automatically prefixes database names with the domain prefix — `brightstar_catalog` not just `catalog`
- MySQL users in Virtualmin are created on hosts `10.0.2.15` and `virtualmin.gym-anything.local`, NOT `localhost`
- Cross-domain GRANT requires knowing the exact MySQL username and host — `brightstar@10.0.2.15` not `brightstar@localhost`
- The verifier accepts both `brightstar_catalog` and `brightstar_brightstar_catalog` as valid DB names
- Agent must query real Sakila categories from `sakila.category` table — fabricated names will fail the cross-reference check
- The video_categories table requires 4 specific columns (id, name, description, created_at) — missing any reduces score
- Agent might try to use phpMyAdmin or Adminer (not installed) instead of Webmin's MySQL module or CLI

## Ground Truth
Sakila categories: Action, Animation, Children, Classics, Comedy, Documentary, Drama, Family, Foreign, Games, Horror, Music, New, Sci-Fi, Sports, Travel

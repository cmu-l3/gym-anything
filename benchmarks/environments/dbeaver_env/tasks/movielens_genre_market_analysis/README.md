# Task: MovieLens Genre Market Analysis

## Domain
Market Research — Consumer Preference Analytics

## Occupation Context
**Market Research Analysts and Marketing Specialists** (GDP impact: $501M, importance=90)
use DBeaver to "query internal data warehouses directly" for market segmentation and
consumer research. **Business Intelligence Analysts** (importance=92) use it to "retrieve
data for analysis." This task reflects the real analyst workflow of exploring a large consumer
rating dataset to identify market segments (genre preferences) and high-value opportunities
(hidden gems).

## Goal
Analyze real MovieLens user rating data (GroupLens Research, UMN) to identify:
1. Top-performing genres by average audience rating (with statistical significance threshold)
2. "Hidden gem" movies — critically loved but under-exposed films

## Database: MovieLens
- **Location**: `/home/ga/Documents/databases/movielens.db`
- **Source**: MovieLens Latest Small Dataset, GroupLens Research, University of Minnesota
  - URL: https://files.grouplens.org/datasets/movielens/ml-latest-small.zip
  - License: Available for research purposes
- **Contents**: ~9,742 movies, ~100,836 ratings from 610 users
- **Tables**: movies, ratings, tags

### Schema
```sql
CREATE TABLE movies (movieId INTEGER PRIMARY KEY, title TEXT, genres TEXT);
-- genres is pipe-separated: 'Action|Comedy|Drama'
CREATE TABLE ratings (userId INTEGER, movieId INTEGER, rating REAL, timestamp INTEGER);
CREATE TABLE tags (userId INTEGER, movieId INTEGER, tag TEXT, timestamp INTEGER);
```

## Expected Deliverables

### 1. DBeaver Connection
- Name: `MovieLens` (exact)

### 2. Genre Analysis CSV: `/home/ga/Documents/exports/genre_analysis.csv`
Columns: `genre`, `avg_rating`, `rating_count`
- 5 rows (top 5 genres with ≥500 ratings)
- Sorted by avg_rating descending

### 3. Hidden Gems CSV: `/home/ga/Documents/exports/hidden_gems.csv`
Columns: `movieId`, `title`, `avg_rating`, `rating_count`
- 10 rows of movies with avg_rating ≥ 4.0 AND rating_count < 50
- Sorted by avg_rating descending

### 4. SQL Script: `/home/ga/Documents/scripts/market_analysis.sql`
The queries used to produce both CSVs.

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| DBeaver 'MovieLens' connection exists | 10 | data-sources.json |
| genre_analysis.csv exists with 5 rows | 20 | file + row count |
| Genre CSV top genre matches ground truth | 20 | genre name comparison |
| hidden_gems.csv exists with 10 rows | 20 | file + row count |
| Hidden gems satisfy criteria (rating ≥4.0, count <50) | 15 | value validation |
| SQL script saved | 15 | file existence + size |

**Pass threshold: 60 points**

## Difficulty Factors
- Genre parsing challenge: genres are pipe-separated in a single TEXT column — agent must
  figure out how to unnest them (SQLite has no built-in SPLIT, requires creative WITH RECURSIVE
  or REPLACE+LIKE approaches, or may approximate by counting via LIKE '%genre%')
- Must apply a minimum rating count filter (≥500) for statistical significance
- Must discover the hidden gems definition from the description (not told what SQL to write)
- Must produce TWO separate CSV files with different schemas
- SQL script saving requires using DBeaver's script save feature

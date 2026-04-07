#!/usr/bin/env python3
"""
Generate deterministic outbreak survey CSV for investigate_waterborne_outbreak task.

Causal structure:
- MunicipalWater -> Ill (RR ~3.2, true cause)
- DailyGlasses -> Ill (dose-response, OR ~1.3/glass)
- UsesFilter -> Ill (protective, RR ~0.4)
- SwimmingPool confounded with MunicipalWater (crude RR ~1.9, adjusted OR ~1.1)
- DaycareContact -> Ill (minor independent, RR ~1.7)
- North neighborhood has highest attack rate (~65%)
"""

import csv
import random
import os

random.seed(42)

N = 200
neighborhoods = ["North", "South", "East", "West", "Central"]
neighborhood_municipal_rate = {
    "North": 0.90, "South": 0.55, "East": 0.60, "West": 0.50, "Central": 0.50
}

sex_male_variants = ["M", "Male", "male"]
sex_female_variants = ["F", "Female", "female"]
water_municipal_variants = ["Tap", "tap", "Municipal", "municipal"]
water_other_options = ["Bottled", "Well"]
ill_yes_variants = ["Yes", "Y", "1"]
ill_no_variants = ["No", "N", "0"]

rows = []
for i in range(N):
    rid = f"R{i+1:03d}"
    hood = neighborhoods[i % 5]  # 40 per neighborhood, interleaved
    age = random.randint(5, 82)
    sex_is_male = random.random() < 0.5
    sex = random.choice(sex_male_variants if sex_is_male else sex_female_variants)

    # Municipal water based on neighborhood
    is_municipal = random.random() < neighborhood_municipal_rate[hood]
    if is_municipal:
        water_source = random.choice(water_municipal_variants)
    else:
        water_source = random.choice(water_other_options)

    # Daily glasses: higher for municipal users
    if is_municipal:
        glasses = max(0, min(8, int(random.gauss(5, 1.8))))
    else:
        glasses = max(0, min(8, int(random.gauss(2, 1.5))))

    # Uses filter: only meaningful for municipal users
    if is_municipal:
        uses_filter = random.random() < 0.30
    else:
        uses_filter = random.random() < 0.10  # rare for non-municipal

    # Swimming pool: strongly correlated with municipal (confounder)
    if is_municipal:
        swims = random.random() < 0.58
    else:
        swims = random.random() < 0.12

    # Daycare contact: independent
    daycare = random.random() < 0.18

    # Illness probability: logistic model
    # Base rate for non-municipal, no filter, no swim, no daycare, glasses=0
    logit = -2.2  # baseline ~10% for fully unexposed
    if is_municipal:
        logit += 2.0  # strong effect
    logit += glasses * 0.15  # dose-response
    if uses_filter:
        logit -= 1.2  # protective
    # Swimming pool: NO independent effect (confounder only)
    if daycare:
        logit += 0.9  # moderate independent effect

    prob_ill = 1 / (1 + 2.718 ** (-logit))
    is_ill = random.random() < prob_ill

    # Messy Ill coding
    if is_ill:
        ill_str = random.choice(ill_yes_variants)
    else:
        ill_str = random.choice(ill_no_variants)

    # Onset date for ill cases (days 1-14, peak around day 5-7)
    onset_date = ""
    if is_ill:
        day = max(1, min(14, int(random.gauss(6, 2.5))))
        onset_date = f"2024-03-{day:02d}"

    rows.append({
        "RespondentID": rid,
        "Neighborhood": hood,
        "Age": age,
        "Sex": sex,
        "WaterSource": water_source,
        "DailyGlasses": glasses,
        "UsesFilter": "Yes" if uses_filter else "No",
        "SwimmingPool": "Yes" if swims else "No",
        "DaycareContact": "Yes" if daycare else "No",
        "Ill": ill_str,
        "OnsetDate": onset_date
    })

# Post-generation: ensure all listed variants appear at least once.
# Patch specific rows (chosen to preserve the same illness status) with missing variants.
def ensure_variant(rows, col, target_val, match_condition=None):
    """Replace one row's col value with target_val if it doesn't already appear."""
    if any(r[col] == target_val for r in rows):
        return  # Already present
    for r in rows[10:]:  # Skip first 10 to avoid edge effects
        if match_condition is None or match_condition(r):
            r[col] = target_val
            return

# Ensure all Sex variants
ensure_variant(rows, 'Sex', 'male', lambda r: r['Sex'] in ('M', 'Male'))
ensure_variant(rows, 'Sex', 'female', lambda r: r['Sex'] in ('F', 'Female'))

# Ensure all WaterSource variants
ensure_variant(rows, 'WaterSource', 'Tap', lambda r: r['WaterSource'] in ('tap', 'Municipal', 'municipal'))
ensure_variant(rows, 'WaterSource', 'Municipal', lambda r: r['WaterSource'] in ('tap', 'Tap', 'municipal'))
ensure_variant(rows, 'WaterSource', 'tap', lambda r: r['WaterSource'] in ('Tap', 'Municipal', 'municipal'))
ensure_variant(rows, 'WaterSource', 'municipal', lambda r: r['WaterSource'] in ('tap', 'Tap', 'Municipal'))

# Write CSV
outpath = os.path.join(os.path.dirname(__file__), "outbreak_survey.csv")
with open(outpath, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=[
        "RespondentID", "Neighborhood", "Age", "Sex", "WaterSource",
        "DailyGlasses", "UsesFilter", "SwimmingPool", "DaycareContact",
        "Ill", "OnsetDate"
    ])
    writer.writeheader()
    writer.writerows(rows)

# Print summary statistics
total = len(rows)
ill_count = sum(1 for r in rows if r["Ill"] in ill_yes_variants)
print(f"Total: {total}, Ill: {ill_count}, Attack Rate: {ill_count/total*100:.1f}%")

# Neighborhood attack rates
for hood in neighborhoods:
    hood_rows = [r for r in rows if r["Neighborhood"] == hood]
    hood_ill = sum(1 for r in hood_rows if r["Ill"] in ill_yes_variants)
    print(f"  {hood}: {len(hood_rows)} total, {hood_ill} ill, AR={hood_ill/len(hood_rows)*100:.1f}%")

# Municipal vs non-municipal
muni_rows = [r for r in rows if r["WaterSource"] in water_municipal_variants]
other_rows = [r for r in rows if r["WaterSource"] not in water_municipal_variants]
muni_ill = sum(1 for r in muni_rows if r["Ill"] in ill_yes_variants)
other_ill = sum(1 for r in other_rows if r["Ill"] in ill_yes_variants)
muni_ar = muni_ill / len(muni_rows) if muni_rows else 0
other_ar = other_ill / len(other_rows) if other_rows else 0
rr = muni_ar / other_ar if other_ar > 0 else float('inf')
print(f"\nMunicipal: {len(muni_rows)} total, {muni_ill} ill, AR={muni_ar*100:.1f}%")
print(f"Other: {len(other_rows)} total, {other_ill} ill, AR={other_ar*100:.1f}%")
print(f"RR (Municipal vs Other): {rr:.2f}")

# Swimming pool crude analysis
swim_rows = [r for r in rows if r["SwimmingPool"] == "Yes"]
noswim_rows = [r for r in rows if r["SwimmingPool"] == "No"]
swim_ill = sum(1 for r in swim_rows if r["Ill"] in ill_yes_variants)
noswim_ill = sum(1 for r in noswim_rows if r["Ill"] in ill_yes_variants)
swim_ar = swim_ill / len(swim_rows) if swim_rows else 0
noswim_ar = noswim_ill / len(noswim_rows) if noswim_rows else 0
swim_rr = swim_ar / noswim_ar if noswim_ar > 0 else float('inf')
print(f"\nSwimmingPool: {len(swim_rows)} total, {swim_ill} ill, AR={swim_ar*100:.1f}%")
print(f"No SwimmingPool: {len(noswim_rows)} total, {noswim_ill} ill, AR={noswim_ar*100:.1f}%")
print(f"RR (Swimming crude): {swim_rr:.2f}")

# Filter analysis
filter_rows = [r for r in rows if r["UsesFilter"] == "Yes"]
nofilter_rows = [r for r in rows if r["UsesFilter"] == "No"]
filter_ill = sum(1 for r in filter_rows if r["Ill"] in ill_yes_variants)
nofilter_ill = sum(1 for r in nofilter_rows if r["Ill"] in ill_yes_variants)
filter_ar = filter_ill / len(filter_rows) if filter_rows else 0
nofilter_ar = nofilter_ill / len(nofilter_rows) if nofilter_rows else 0
filter_rr = filter_ar / nofilter_ar if nofilter_ar > 0 else float('inf')
print(f"\nUsesFilter: {len(filter_rows)} total, {filter_ill} ill, AR={filter_ar*100:.1f}%")
print(f"No Filter: {len(nofilter_rows)} total, {nofilter_ill} ill, AR={nofilter_ar*100:.1f}%")
print(f"RR (Filter crude): {filter_rr:.2f}")

# Daycare analysis
dc_rows = [r for r in rows if r["DaycareContact"] == "Yes"]
nodc_rows = [r for r in rows if r["DaycareContact"] == "No"]
dc_ill = sum(1 for r in dc_rows if r["Ill"] in ill_yes_variants)
nodc_ill = sum(1 for r in nodc_rows if r["Ill"] in ill_yes_variants)
dc_ar = dc_ill / len(dc_rows) if dc_rows else 0
nodc_ar = nodc_ill / len(nodc_rows) if nodc_rows else 0
dc_rr = dc_ar / nodc_ar if nodc_ar > 0 else float('inf')
print(f"\nDaycare: {len(dc_rows)} total, {dc_ill} ill, AR={dc_ar*100:.1f}%")
print(f"No Daycare: {len(nodc_rows)} total, {nodc_ill} ill, AR={nodc_ar*100:.1f}%")
print(f"RR (Daycare crude): {dc_rr:.2f}")

# HighConsumption (>=5 glasses)
high_rows = [r for r in rows if r["DailyGlasses"] >= 5]
low_rows = [r for r in rows if r["DailyGlasses"] < 5]
high_ill = sum(1 for r in high_rows if r["Ill"] in ill_yes_variants)
low_ill = sum(1 for r in low_rows if r["Ill"] in ill_yes_variants)
high_ar = high_ill / len(high_rows) if high_rows else 0
low_ar = low_ill / len(low_rows) if low_rows else 0
high_rr = high_ar / low_ar if low_ar > 0 else float('inf')
print(f"\nHighConsumption (>=5): {len(high_rows)} total, {high_ill} ill, AR={high_ar*100:.1f}%")
print(f"LowConsumption (<5): {len(low_rows)} total, {low_ill} ill, AR={low_ar*100:.1f}%")
print(f"RR (HighConsumption crude): {high_rr:.2f}")

print(f"\nCSV written to: {outpath}")

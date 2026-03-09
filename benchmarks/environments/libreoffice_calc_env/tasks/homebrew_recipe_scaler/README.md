# Homebrew Recipe Scaler Task

**Difficulty**: 🟡 Medium  
**Skills**: Proportional scaling, formula creation, domain-specific calculations  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Scale down a homebrew beer recipe from 5 gallons to 3 gallons while calculating brewing parameters. This task tests proportional reasoning, formula application with absolute references, and domain-specific calculations (ABV from gravity readings).

## Task Description

The agent must:
1. Calculate the scale factor (3/5 = 0.6) in a designated cell
2. Apply scaling formulas to all ingredients using absolute reference to scale factor
3. Calculate ABV (Alcohol By Volume) using the brewing formula: ABV = (OG - FG) × 131.25
4. Ensure scaled amounts are practical and formulas are properly structured

## Starting State

- LibreOffice Calc opens with a pre-populated Belgian Witbier recipe
- Recipe contains: grain bill, hop schedule, yeast, and other ingredients
- Original batch size: 5 gallons
- Target batch size: 3 gallons
- Original Gravity (OG): 1.048
- Final Gravity (FG): 1.010

## Recipe Structure

**Grains:**
- Pilsner Malt: 6.5 lbs
- Wheat Malt: 3.0 lbs
- Oats (flaked): 0.5 lbs

**Hops & Spices:**
- Hallertau: 1.0 oz (60 min)
- Coriander: 0.75 oz (5 min)

**Yeast & Additions:**
- Belgian Wit Yeast: 1 packet
- Orange Peel: 1.0 oz

## Expected Results

- **Scale Factor (B2)**: 0.6 or formula =3/5
- **Scaled Grains**: All grain amounts × 0.6 (e.g., 6.5 lbs → 3.9 lbs)
- **Scaled Hops**: All hop amounts × 0.6 (e.g., 1.0 oz → 0.6 oz)
- **Scaled Yeast**: 1 packet (discrete items round to 1 minimum)
- **ABV (B21)**: ~4.99% calculated using formula =(B19-B20)*131.25

## Verification Criteria

1. ✅ **Scale Factor Correct**: Cell B2 contains 0.6 or =3/5 (±0.01)
2. ✅ **Scaling Formulas Present**: At least 80% of ingredients use formulas with absolute reference ($B$2)
3. ✅ **ABV Calculated Correctly**: Formula produces 4.5-5.5% using standard brewing equation
4. ✅ **Practical Values**: All scaled amounts within reasonable brewing ranges
5. ✅ **Formula Integrity**: Scaled amounts are formulas, not hard-coded values

**Pass Threshold**: 75% (requires at least 4 out of 5 criteria)

## Skills Tested

- Proportional scaling calculations
- Absolute vs. relative cell references
- Domain-specific formula application
- Mathematical function usage (ROUND, IF)
- Formula copying and dragging
- Numeric precision and formatting

## Tips

- Calculate scale factor first: =3/5 or =0.6 in cell B2
- Use absolute reference: =$B$2 when scaling ingredients
- ABV formula: =(OG_cell - FG_cell) * 131.25
- Gravity values are in cells B19 (OG) and B20 (FG)
- For discrete items (yeast packets), use =IF(B17*$B$2<1, 1, ROUND(B17*$B$2,0))
- Verify formulas are working (not just values) before saving
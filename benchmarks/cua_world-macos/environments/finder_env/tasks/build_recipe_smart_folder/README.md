# Task: build_recipe_smart_folder

## Overview

The agent has 20 recipe `.txt` files in ~/Downloads with human-readable names indicating cuisine type (e.g. "Pad Thai Noodles.txt", "Sourdough Bread Beginner.txt"). The task tests whether an agent can:

1. Classify and route files into cuisine-specific subfolders
2. Rename files to a canonical snake_case format
3. Apply Finder color tags to all files
4. Create a macOS Smart Folder (.savedSearch plist) scoped to the recipe library

This is a realistic personal-use scenario: a home cook who has accumulated recipe files from many sources wants to build a searchable, browsable recipe library in Finder.

## End State (Goal)

```
~/Documents/Recipes/
├── Italian/
│   ├── pasta_carbonara_from_nonna.txt      [Yellow tag]
│   ├── homemade_margherita_pizza.txt       [Yellow tag]
│   ├── risotto_ai_funghi.txt               [Yellow tag]
│   ├── tiramisu_classic.txt                [Yellow tag]
│   └── osso_buco_milanese.txt              [Yellow tag]
├── Asian/   (5 files, Yellow tag each)
├── Mexican/ (4 files, Yellow tag each)
├── Baking/  (3 files, Yellow tag each)
└── Other/   (3 files, Yellow tag each)

~/Library/Saved Searches/My Recipes.savedSearch
  → searches for kMDItemUserTags == "Yellow" within ~/Documents/Recipes/
```

## Success Criteria

| Criterion | Points | Details |
|-----------|--------|---------|
| C1: Five cuisine subfolders exist | 15 | 3 pts × 5 |
| C2: Files in correct cuisine folder | 30 | proportional (20 files) |
| C3: Filenames in lowercase_underscore format | 25 | proportional |
| C4: Yellow tag on every file | 20 | proportional (20 files) |
| C5: Valid Smart Folder plist | 10 | exists (4) + Yellow in query (3) + Recipes scope (3) |
| **Total** | **100** | Pass at ≥70 |

## Verification Strategy

`export_result.sh` reads:
- `folders_exist` — `os.path.isdir` for each of 5 subfolders
- `files_by_folder` — `os.listdir` per subfolder
- `tags_by_file` — `mdls -name kMDItemUserTags` per file
- `smart_folder_exists` — `os.path.isfile` on ~/Library/Saved Searches/My Recipes.savedSearch
- `smart_folder_content` — raw bytes as hex for plistlib parse in verifier

Verifier checks cuisine routing, filename format (regex `[a-z][a-z0-9_]*`), tags, and plist structure.

## File → Cuisine Mapping

| File (original name) | Cuisine | Renamed |
|---------------------|---------|---------|
| Pasta Carbonara from Nonna.txt | Italian | pasta_carbonara_from_nonna.txt |
| Homemade Margherita Pizza.txt | Italian | homemade_margherita_pizza.txt |
| Risotto ai Funghi.txt | Italian | risotto_ai_funghi.txt |
| Tiramisu Classic.txt | Italian | tiramisu_classic.txt |
| Osso Buco Milanese.txt | Italian | osso_buco_milanese.txt |
| Pad Thai Noodles.txt | Asian | pad_thai_noodles.txt |
| Japanese Miso Soup.txt | Asian | japanese_miso_soup.txt |
| Korean Bibimbap Bowl.txt | Asian | korean_bibimbap_bowl.txt |
| Chicken Fried Rice Easy.txt | Asian | chicken_fried_rice_easy.txt |
| Vietnamese Pho Broth.txt | Asian | vietnamese_pho_broth.txt |
| Street Tacos al Pastor.txt | Mexican | street_tacos_al_pastor.txt |
| Homemade Guacamole.txt | Mexican | homemade_guacamole.txt |
| Black Bean Enchiladas.txt | Mexican | black_bean_enchiladas.txt |
| Churros with Chocolate.txt | Mexican | churros_with_chocolate.txt |
| Sourdough Bread Beginner.txt | Baking | sourdough_bread_beginner.txt |
| Chocolate Chip Cookies Classic.txt | Baking | chocolate_chip_cookies_classic.txt |
| Banana Bread Moist.txt | Baking | banana_bread_moist.txt |
| Greek Salad Simple.txt | Other | greek_salad_simple.txt |
| Moroccan Lamb Tagine.txt | Other | moroccan_lamb_tagine.txt |
| French Onion Soup.txt | Other | french_onion_soup.txt |

## Edge Cases and Potential Issues

- Smart Folder creation via Finder requires clicking File → New Smart Folder, adding tag criteria, scoping to ~/Documents/Recipes/, and saving. The plist must include a RawQuery with "Yellow" and a SearchScopes containing the Recipes path.
- Rename in Finder requires clicking once to select, pressing Return (not Enter on numeric keypad) to enter rename mode.
- The verifier accepts any plist that mentions "Yellow" in the query string — it does not validate the exact MDQuery syntax.

library(MASS)
data(fgl)

cat("Output Dir Claim: /home/ga/RProjects/output
")
cat("Required Files Claim: glass_geometric_means.csv, glass_clr_transformed.csv, glass_biplot.png, glass_ternary_si_na_ca.png
")

cat("Dataset Claim: MASS::fgl
")
cat(sprintf("Exists: %s
", exists("fgl")))

cat(sprintf("Number of rows: %d
", nrow(fgl)))

expected_types_claim <- c("WinF", "WinNF", "Veh", "Con", "Tabl", "Head")
actual_types <- unique(fgl$type)
cat("Expected Types Claim:
")
cat(sprintf("Actual Types: %s
", paste(actual_types, collapse=", ")))
cat(sprintf("Levels: %s
", paste(levels(fgl$type), collapse=", ")))

chemical_columns_claim <- c("Na", "Mg", "Al", "Si", "K", "Ca", "Ba", "Fe")
actual_columns <- colnames(fgl)
cat("Chemical Columns Claim:
")
cat(sprintf("Actual Columns: %s
", paste(actual_columns, collapse=", ")))


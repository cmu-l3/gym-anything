library(sf)
library(spdep)
nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)
print(colnames(nc))

nb <- poly2nb(nc)
lw <- nb2listw(nb)

for (v in colnames(nc)) {
  if (is.numeric(nc[[v]])) {
    tryCatch({
      m <- moran.test(nc[[v]], lw)
      cat(sprintf("Var: %s, Moran I: %f\n", v, m$estimate[1]))
    }, error = function(e) {})
  }
}

nc$RATE79 <- (nc$SID79 / nc$BIR79) * 1000
m79 <- moran.test(nc$RATE79, lw)
cat(sprintf("Var: RATE79, Moran I: %f\n", m79$estimate[1]))


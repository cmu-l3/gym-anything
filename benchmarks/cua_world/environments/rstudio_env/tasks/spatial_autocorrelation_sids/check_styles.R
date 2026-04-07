library(sf)
library(spdep)
nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)
RATE <- (nc$SID74 / nc$BIR74) * 1000

nb <- poly2nb(nc)
for (s in c("W", "B", "C", "U", "minmax", "S")) {
  lw <- nb2listw(nb, style=s)
  m <- moran.test(RATE, lw)
  cat(sprintf("Style %s: %f\n", s, m$estimate[1]))
}

nb_rook <- poly2nb(nc, queen=FALSE)
for (s in c("W", "B", "C", "U", "minmax", "S")) {
  lw <- nb2listw(nb_rook, style=s)
  m <- moran.test(RATE, lw)
  cat(sprintf("Rook Style %s: %f\n", s, m$estimate[1]))
}


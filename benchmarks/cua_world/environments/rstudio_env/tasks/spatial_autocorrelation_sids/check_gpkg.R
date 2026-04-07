library(sf)
library(spdep)
sids <- st_read(system.file("shapes/sids.gpkg", package="spData"), quiet=TRUE)
sids$RATE <- (sids$SID74 / sids$BIR74) * 1000
nb <- poly2nb(sids)
lw <- nb2listw(nb)
print("Moran sids.gpkg rate:")
print(moran.test(sids$RATE, lw)$estimate[1])

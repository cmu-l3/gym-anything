library(sf)
library(spdep)
nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)
FT <- sqrt(1000) * (sqrt(nc$SID74/nc$BIR74) + sqrt((nc$SID74+1)/nc$BIR74))
nb <- poly2nb(nc)
lw <- nb2listw(nb)
m <- moran.test(FT, lw)
print(m$estimate[1])

# Is it just raw rate, but not per 1000?
# Moran I is scale invariant, so per 1000 or not, it's the same.

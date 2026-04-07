library(sf)
library(spdep)
nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)
nc$RATE <- (nc$SID74 / nc$BIR74) * 1000

nb <- poly2nb(nc) # Default queen=TRUE
lw <- nb2listw(nb)
m <- moran.test(nc$RATE, lw)
print("Moran I for Rate:")
print(m$estimate[1])

print("Moran I for Raw Counts (SID74):")
m2 <- moran.test(nc$SID74, lw)
print(m2$estimate[1])


library(sf)
library(spdep)

nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)
nc$SID74_RATE <- (nc$SID74 / nc$BIR74) * 1000

nb <- poly2nb(nc, queen=TRUE)
lw <- nb2listw(nb, style="W", zero.policy=TRUE)

m <- moran.test(nc$SID74_RATE, lw, zero.policy=TRUE)
print(m$estimate[1])

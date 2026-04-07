library(sf)
library(spdep)
nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)
sids_rate <- (nc$SID74 / nc$BIR74) * 1000
nb <- poly2nb(nc, queen=TRUE)
listw <- nb2listw(nb, style="W", zero.policy=TRUE)
m <- moran.test(sids_rate, listw, zero.policy=TRUE)
print(m$estimate[1])

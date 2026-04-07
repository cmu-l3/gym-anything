library(sf)
library(spdep)
nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)
RATE <- ((nc$SID74 + nc$SID79) / (nc$BIR74 + nc$BIR79)) * 1000

nb <- poly2nb(nc)
lw <- nb2listw(nb)
print("Moran Both:")
print(moran.test(RATE, lw)$estimate[1])


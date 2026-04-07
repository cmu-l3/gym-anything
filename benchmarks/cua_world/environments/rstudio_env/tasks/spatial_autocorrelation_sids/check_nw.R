library(sf)
library(spdep)
nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)
NW <- (nc$NWBIR74 / nc$BIR74)
nb <- poly2nb(nc)
lw <- nb2listw(nb)
print("Moran NW:")
print(moran.test(NW, lw)$estimate[1])

# Is it distance based neighbors?
coords <- st_centroid(st_geometry(nc))
nb_knn <- knn2nb(knearneigh(coords, k=4))
print("KNN4 Rate:")
print(moran.test((nc$SID74 / nc$BIR74), nb2listw(nb_knn))$estimate[1])


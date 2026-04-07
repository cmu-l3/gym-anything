library(sf)
library(spdep)
nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)
RATE <- (nc$SID74 / nc$BIR74) * 1000
coords <- st_centroid(st_geometry(nc))
dists <- unlist(nbdists(knn2nb(knearneigh(coords, k=1)), coords))
max_1nn <- max(dists)

nb_dist <- dnearneigh(coords, 0, max_1nn)
lw_dist <- nb2listw(nb_dist)
print(moran.test(RATE, lw_dist)$estimate[1])


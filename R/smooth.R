

# Load Data ---------------------------------------------------------------
opga <- readr::read_rds(here::here('Data','Clean','opga.rds')) |>
  mutate(MR = Deaths / pop * 1000,
         eMR = sum(Deaths) / sum(pop) * 1000,
         eDeaths = sum(Deaths) / sum(pop) * pop,
         SMR = Deaths / eDeaths,
         ID = row_number())

# Smoothing ---------------------------------------------------------------

# Create neighborhood object
nb <- spdep::poly2nb(opga$geometry, queen = FALSE)
W <- spdep::nb2mat(nb, style = 'B')

# Proximity matrix (based on distance between county centroids)
D <- sf::st_centroid(opga$geometry) |> 
  sf::st_coordinates() |>
  dist() |>
  as.matrix()

# Add adjacency-smoothed mortality rate
opga$asMR <- mapply(x = 1:nrow(opga), x_nb = nb,
                    \(x, x_nb){
                      x_w_nb <- c(x, x_nb)
                      mean(opga$Deaths[x_w_nb] / opga$pop[x_w_nb]) * 1000})

# Add distance-smoothed mortality rate
opga$dsMR <- mapply(x = 1:nrow(opga), x_nb = nb,
                    \(x, x_nb){
                      x_w_nb <- c(x, x_nb)
                      w <- D[x_w_nb, x]
                      w[1] <- min(w[w > 0])
                      weighted.mean(opga$Deaths[x_w_nb] / opga$pop[x_w_nb], 1 / w) * 1000})

# Add Bayesian-smoothed mortality rate (using INLA)
bym_model <- INLA::inla(Deaths ~ 1 + f(ID, model = "bym", graph = W),
                        data = opga, offset = log(pop), family = "poisson",
                        control.compute = list(dic = TRUE, waic = TRUE, cpo = TRUE),
                        control.predictor = list(compute = TRUE))

opga$bsMR <- bym_model$summary.fitted.values[, '0.5quant'] / opga$pop * 1000



# Export Results ----------------------------------------------------------
write_rds(opga, here::here('Data','Clean','opga_smooth.rds'))


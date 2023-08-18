# Program Name: smooth.R
# Author:       Jacob Englert
# Date:         05MAY2022
# Purpose:      Augment a dataset with adjacency, distance, and BYM smoothing.

# Smoothing ---------------------------------------------------------------

smooth <- function(data){
  
  data <- data |>
    dplyr::mutate(MR = Deaths / pop * 1000,
                  eDeaths = sum(Deaths) / sum(pop) * pop,
                  SMR = Deaths / eDeaths)
  
  # Create neighborhood object
  nb <- spdep::poly2nb(data$geometry, queen = FALSE)
  W <- spdep::nb2mat(nb, style = 'B')

  # Proximity matrix (based on distance between county centroids)
  D <- sf::st_centroid(data$geometry) |> 
    sf::st_coordinates() |>
    dist() |>
    as.matrix()
  
  # Add adjacency-smoothed mortality rate
  data$aMR <- mapply(x = 1:nrow(data), x_nb = nb,
                     \(x, x_nb){
                       x_w_nb <- c(x, x_nb)
                       mean(data$Deaths[x_w_nb] / data$pop[x_w_nb]) * 1000})
  data$aDeaths <- data$aMR / 1000 * data$pop

  # Add distance-smoothed mortality rate
  data$dMR <- mapply(x = 1:nrow(data), x_nb = nb,
                     \(x, x_nb){
                       x_w_nb <- c(x, x_nb)
                       w <- D[x_w_nb, x]
                       w[1] <- min(w[w > 0])
                       weighted.mean(data$Deaths[x_w_nb] / data$pop[x_w_nb], 1 / w) * 1000})
  data$dDeaths <- data$dMR / 1000 * data$pop

  # Add Bayesian-smoothed mortality rate (using INLA)
  bym_model <- INLA::inla(Deaths ~ 1 + f(ID, model = "bym", graph = W),
                          data = data, offset = log(pop), family = "poisson",
                          control.compute = list(dic = TRUE, waic = TRUE, cpo = TRUE),
                          control.predictor = list(compute = TRUE))

  data$bMR <- bym_model$summary.fitted.values[, '0.5quant'] / data$pop * 1000
  data$bDeaths <- data$bMR / 1000 * data$pop
  
  

  return(data)
}

# Program Name: power.R
# Author:       Jacob Englert
# Date:         05MAY2022
# Purpose:      Conduct a power analysis of various clustering/smoothing schemes

# Load Packages -----------------------------------------------------------
library(tidyverse)
library(sf)
library(spdep)
library(smerc) 
library(INLA)


# Retrieve FindClusters Function from Cluster.R ---------------------------
source("R/cluster.R")

data <- read_rds(here::here('Data','Clean','opga.rds'))

# Create neighborhood object
nb <- spdep::poly2nb(data$geometry, queen = FALSE)
W <- spdep::nb2mat(nb, style = 'B')

# Proximity matrix (based on distance between county centroids)
centroids <- sf::st_centroid(data$geometry) |> 
  sf::st_coordinates()
D <- centroids |>
  dist() |>
  as.matrix()


# Create copy of neighborhood object with central region included
nb <- lapply(1:nrow(data), \(x) c(x, nb[[x]]))

# Simulate Clustering Scenarios -------------------------------------------

# Specify center of circular cluster(s)
c_regions <- c('DeKalb','Early','Gilmer')
c_ids <- data$ID[data$Geography %in% c_regions][order(na.omit(match(data$Geography, c_regions)))]
c_sizes <- rep(5, length(c_regions))
n_clus <- length(c_regions)

# Get k-nearest neighbors for each region
c_nn <- smerc::knn(centroids, longlat = TRUE, k = 10, d = D)

# Create vector of k nearest neighbors for each center specified
clusters <- lapply(1:n_clus, \(x) c_nn[[center[x]]][1:c_sizes[x]])
names(clusters) <- c_regions

# Detailed cluster label vector
cluster_labs <- rep('None', nrow(data))
for(i in 1:n_clus) cluster_labs[clusters[[i]]] <- c_regions[i]
  

# Set delta and epsilon (Waller, Hill, Rudd 2006)
d <- data$ID %in% unlist(clusters) # 1 if in cluster, 0 otherwise
E <- c(0.5, 1, 1.5, 2) # cluster relative risk increase

# Confirm names and locations of counties included in clusters
# sapply(clusters, function(x) data$Geography[x])
# data |> ggplot() + geom_sf(aes(geometry = geometry, fill = cluster_labs))

# Simulate datasets, keeping the total number of cases fixed
nsim <- 10
set.seed(4303)
sim_data <- sapply(e, 
                   \(x) rmultinom(n = nsim, size = sum(data$Deaths),
                                  prob = data$pop * (1 + d * x) / sum(data$pop * (1 + d * x))), 
                   simplify = 'array')

# # Confirm regions in the cluster are showing higher SMR
# sim_data |>
#   matrix(ncol = prod(dim(sim_data)[2:3])) |>
#   as.data.frame() |>
#   mutate(county = data$Geography) |>
#   pivot_longer(cols = -county) |>
#   mutate(e = factor(rep(rep(E, each = nsim), times = nrow(data))),
#          exp = rep(sum(data$Deaths) * data$pop / sum(data$pop), each = nsim * length(E))) |>
#   mutate(SMR = value / exp,
#          cluster = rep(cluster_labs, each = nsim * length(E))) |>
#   group_by(e, county) |>
#   filter(median(SMR) > 1) |>
#   ggplot(aes(x = SMR, y = reorder(county, SMR, FUN = median), fill = cluster)) +
#   geom_boxplot() +
#   facet_wrap(~e, scales = 'free')
# 
# # Check size of cluster to help determine parameters
# 
# # Print observed (true) cluster members, total populations and cases
# sapply(clusters, function(x) data$Geography[x])
# sapply(clusters, function(x) sum(data$pop[x]))
# sapply(clusters, function(x) sum(data$Deaths[x]))
# 
# # Print mean total observed (simulated) cases for each value of E
# apply(sim_data[unlist(clusters),,], 3, function(x) sum(rowMeans(x)))
# 
# # Print mean cluster observed (simulated) cases for each value of E
# sapply(clusters, function(x) apply(sim_data[x,,], 3, function(y) sum(rowMeans(y))))

# Run Simulation ----------------------------------------------------------

# Create storage
smooth <- list('Obs','Adj','ID','BYM')
test <- list('TB','BN','KD')
results <- array(dim = c(length(E), nsim, length(smooth), length(test), nrow(data)), 
              dimnames = list(E = E,
                              sim = 1:nsim,
                              smooth = smooth,
                              test = test,
                              county = data$Geography))

# Specify Cluster Test Parameters
tb_nstar <- max(sapply(clusters, function(x) sum(data$pop[x])))
bn_cstar <- apply(sapply(clusters, function(x) apply(sim_data[x,,], 3, function(y) sum(rowMeans(y)))), 1, min)

source('R/smooth.R')
source('R/cluster.R')

# Run Simulation
set.seed(1919)
pb <- progress::progress_bar$new(total = nsim * length(E))
for(e in 1:length(E)){
  
  for(s in 1:nsim){

    # 0) Get new "observed" dataset and update constant risk expectation
    sim_obs <- sim_data[, s, e]
    tmp <- data
    tmp$Deaths <- sim_obs

    # 1) Get smoothed values
    tmp <- smooth(tmp)

    # 2) Apply Cluster Detection Tests
    c_res <- tmp[,c('Deaths','aDeaths','dDeaths','bDeaths')] |>
      lapply(\(obs) find_clusters(obs = obs, pop = tmp$pop, 
                                  tb_nstar = tb_nstar, bn_cstar = bn_cstar[e],
                                  coords = centroids))
    
    # 3) Store Results
    for(s_idx in 1:4){
      for(t_idx in c('TB','BN','KD')){
        results[e, s, s_idx, t_idx, ] <- data$ID %in% filter(c_res[[s_idx]], 
                                                             test == t_idx &
                                                             !is.na(cluster_id))$ID
      }
    }
    
    pb$tick()
  }
}

# Calculate Accuracy Measures ---------------------------------------------

# E, sim, smooth, test, county

# Mean Overall Sensitivity (ability to detect positives as positive)
sens <- apply(results[,,,,d], c(1,3,4), function(x) mean(rowSums(x)/sum(d))) # Verified

# Mean Specificity (ability to detect negatives as negative)
spec <- apply(!results[,,,,!d], c(1,3,4), function(x) mean(rowSums(x)/sum(!d))) # Verified

# Mean PPV (probability a positive test is actually positive)
#P.C <- sum(D)/length(D)               # Probability of cluster
#P.D <- apply(temp[,,,,], c(1,3,4), function(x) mean(rowSums(x)/length(D))) # Probability of detecting a cluster
#PPV <- sens*P.C/P.D

PPV <- apply(results, c(1,3,4), function(x) mean(apply(x, 1, function(y) mean(which(y) %in% which(d))))) # Verified?

# Mean NPV (probability a negative test is actually negative)
#NPV <- spec*(1 - P.C)/(1 - P.D)

NPV <- apply(results, c(1,3,4), function(x) mean(apply(x, 1, function(y) mean(which(!y) %in% which(!d))))) # Verified?

# Exact Power (Schuldeln et al. 2021)
EP <- apply(results, c(1,3,4), function(x) mean(apply(x[,d], 1, all) & apply(x[,!d] == FALSE, 1, all))) # Verified

# Minimum Power (Schuldeln et al. 2021)
MP <- apply(results[,,,,d], c(1,3,4), function(x) mean(rowSums(x) > 0)) # Verified, only for one cluster

# Correct Classification
CC <- apply(results, c(1,3,4), function(x) mean(colMeans(apply(x, 1, function(y) y == d)))) # Verified


# Visual Comparison -------------------------------------------------------

# Create data frame of results
sum_res <- data.frame(rbind(matrix(sens, nrow = prod(dim(sens)[1:2])),
                            matrix(spec, nrow = prod(dim(spec)[1:2])),
                            matrix(PPV, nrow = prod(dim(PPV)[1:2])),
                            matrix(NPV, nrow = prod(dim(NPV)[1:2])),
                            matrix(EP, nrow = prod(dim(EP)[1:2])),
                            matrix(MP, nrow = prod(dim(MP)[1:2])),
                            matrix(CC, nrow = prod(dim(CC)[1:2])))) |>
  mutate(Smoothing = rep(c('Obs','Adj','ID','BYM'), each = 4, times = 7), # 4 smooth x 7 measures
         Measure = rep(c('Sens','Spec','PPV','NPV','EP','MP','CC'), each = 4*length(E)),
         E = rep(E, times = 4*7)) |> # 4 smooth x 7 measures
  mutate(Smoothing = factor(Smoothing, levels = c('Obs','Adj','ID','BYM'))) %>%
  rename(TB = X1, BN = X2, KD = X3) %>%
  pivot_longer(cols = c(TB, BN, KD), names_to = 'Test') %>%
  mutate(Test = case_when(Test == 'TB' ~ 'Turnbull (1990)',
                          Test == 'KD' ~ 'Kulldorff (1997)',
                          Test == 'BN' ~ 'Besag-Newell (1991)'))

# Save Results
# simID <- paste0(paste0(sort(substr(c_regions, 1, 3)),
#                 lengths(clusters), collapse = '_'),
#                 '_sim', nsim)
# write_rds(results, file = paste0('Simulation Results/', simID, '.rds'))
# write_csv(sum_res, file = paste0('Simulation Results/', simID, '.csv'))

# Plot Accuracy Results
sum_res |>
  #filter(!(Test == 'Turnbull (1990)')) %>%
  ggplot(aes(x = E, y = value, color = Smoothing)) +
  geom_point() +
  geom_line() +
  facet_grid(Measure~Test, scales = 'free') +
  theme_bw()


  

# Extras ------------------------------------------------------------------

# Plot frequency captured
#temp <- readRDS('Simulation Results/DeK5_Ear5_Gil5_sim100.rds')
  
tempdf <- as.data.frame(ftable(apply(results, c(1,3,4,5), mean)))
res <- data %>%
  left_join(tempdf, by = c("Geography" = "county")) %>%
  filter(test == 'KD')

borders <- data %>%
  mutate(cluster = cluster_labs) %>%
  group_by(cluster) %>%
  summarise(geometry = sf::st_union(geometry)) %>%
  filter(cluster != 'None')

simplot <- res %>%
  #ggplot(aes(fill = cut(Freq, breaks = seq(0, 1, 0.2)))) + #unique(quantile(Freq, seq(0,1,0.02))), include.lowest = TRUE))) +
  ggplot(aes(fill = Freq, geometry = geometry)) +
  geom_sf() +
  geom_sf(data = borders, fill = NA, color = 'black', size = 0.75) +
  scale_fill_distiller(palette = "YlOrRd", limits = c(0,1)) +
  #scale_fill_brewer(type = 'seq', palette = "YlOrRd") +
  facet_grid(E~smooth) +
  theme(axis.ticks = element_blank(), axis.text = element_blank()) +
  labs(title = 'Cluster Identification Probabilities',
       subtitle = paste('Simulation ID:', simID),
       fill = 'Pr(ID)')
ggsave(plot = simplot,
       filename = here::here('Figures','Simulation', paste0(simID,'.png')), 
       width = 8.5, height = 6.5)

  
# Manually Edit smerc::stat.poisson ---------------------------------------
# tall[good][which(tall[good] < 0)] = 0 <- copy this at the end of the function
# trace(stat.poisson, edit = TRUE)
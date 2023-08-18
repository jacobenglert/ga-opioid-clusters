# Program Name: cluster.R
# Author:       Jacob Englert
# Date:         05MAY2022
# Purpose:      Augment a dataset with clusters found using Turnbull, Besage &
#               Newell, and Kulldorff approaches.

# Obtain centroid coordinates
get_coords <- function(data){
  sf::st_centroid(data$geometry) |> sf::st_coordinates()
}

# Run cluster detection tests
find_clusters <- function(obs, pop, exp = sum(obs) / sum(pop) * pop,
                          tb_nstar = 100000, 
                          bn_cstar = tb_nstar / sum(pop) * sum(obs), 
                          kd_ub = max(tb_nstar, max(pop) + 1) / sum(pop), 
                          kd_min = 2,
                          alpha = 0.1, nsim = 999, 
                          coords, longlat = TRUE){
  
  # Quiets noisy functions
  quiet <- function(x) { 
    suppressWarnings({
      sink(tempfile()) 
      on.exit(sink()) 
      invisible(force(x))
    })
  } 
  
  # Turnbull (1990)
  tb_test <- quiet(smerc::cepp.test(cases = obs, pop = pop, ex = exp, 
                                    nstar = tb_nstar, alpha = alpha, nsim = nsim,
                                    simdist = "poisson",
                                    coords = coords, longlat = longlat))
  
  # Besag and Newell (1991)
  bn_test <- quiet(smerc::bn.test(cases = obs, pop = pop, ex = exp,
                                  cstar = bn_cstar, alpha = alpha, 
                                  coords = coords, longlat = longlat))
  
  # Kulldorff (1997)
  kd_test <- quiet(smerc::scan.test(cases = obs, pop = pop, ex = exp,
                                    ubpop = kd_ub, min.cases = kd_min, 
                                    alpha = alpha, nsim = nsim, 
                                    coords = coords, longlat = longlat, 
                                    simdist = "poisson"))
  
  # Store region IDs, cluster association, and associated cluster p-values
  tests <- list(tb_test, bn_test, kd_test)
  parse_test <- function(test, alpha){
    ids_list <- lapply(test$clusters, '[[', 'locids')
    pvals_list <- lapply(test$clusters, '[[', 'pvalue')
    
    ids <- unlist(ids_list)
    clusters <- rep(seq_along(ids_list), times = lengths(ids_list))
    pvals <- rep(unlist(pvals_list), times = lengths(ids_list))
    
    sig <- which(pvals < alpha)
    
    return(data.frame(ID = ids[sig], cluster_id = clusters[sig], pvalue = pvals[sig]))
  }
  results <- lapply(tests, \(t) parse_test(t, alpha)) |>
    setNames(c('tb','bn','kd')) |>
    dplyr::bind_rows(.id = 'test')
  
  template <- tidyr::crossing(ID = seq_along(pop), test = unique(results$test))
  
  return(dplyr::left_join(template, results, by = c('ID','test')))
}


combine_results <- function(data, smooth_list){
  
  all_smooth <- smooth_list |>
    dplyr::bind_rows(.id = 'smooth')
  
  data_clus <- data |>
    dplyr::left_join(all_smooth, by = 'ID')

  return(data_clus)  
}
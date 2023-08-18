
create_map <- function(data){

  plot <- data |>
    dplyr::mutate(is_cluster = ifelse(is.na(cluster_id), 'Not a cluster', 'Cluster')) |>
    ggplot(aes(fill = is_cluster, geometry = geometry)) +
    geom_sf() +
    # geom_sf_pattern(aes(pattern_angle = test, pattern = test), pattern_spacing = .03, pattern_size = .2) +
    # scale_pattern_angle_manual(values = c(45, 135, 0, 90)) +
    # scale_pattern_manual(values = c('stripe','stripe',NA,'stripe')) +
    # scale_pattern_type_manual(values = c('stripe','wave','crosshatch',NA)) +
    # scale_fill_distiller(palette = "YlOrRd") +
    facet_grid(test~smooth) +
    theme_bw() +
    labs(fill = '')

  return(plot)
}

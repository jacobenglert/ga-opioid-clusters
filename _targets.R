
# Load packages required to define the pipeline
library(targets)
library(tarchetypes)

# Set target options
tar_option_set(
  # packages that your targets need to run
  packages = c("tidyverse", "tigris", "tidycensus", "sf", "spdep", "here", "smerc", "readxl", "INLA"), 
  # storage format
  format = "rds"
)

# Run the R scripts in the R/ folder with your custom functions
tar_source()

# Target workflow
data_targets <- list(
  tar_target(
    oasis,
    here::here("Data","Raw","oasis_opioids.xlsx")
  ),
  tar_target(
    opga,
    obtain_data(oasis, 2021)
  )
)

smooth_targets <- list(
  tar_target(
    opga_smooth,
    smooth(opga)
  )
)

cluster_targets <- list(
  tar_target(coords, get_coords(opga_smooth)),
  tar_target(pop, opga_smooth$pop),
  tar_target(
    orig,
    find_clusters(obs = opga_smooth$Deaths, pop = pop, coords = coords)
  ),
  tar_target(
    adj,
    find_clusters(obs = opga_smooth$aDeaths, pop = pop, coords = coords)
  ),
  tar_target(
    dist,
    find_clusters(obs = opga_smooth$dDeaths, pop = pop, coords = coords)
  ),
  tar_target(
    bym,
    find_clusters(obs = opga_smooth$bDeaths, pop = pop, coords = coords)
  ),
  tar_target(
    clusters,
    combine_results(opga_smooth, list(orig = orig, adj = adj, dist = dist, bym = bym))
  )
)

map_targets <- list(
  tar_target(
    map,
    create_map(clusters)
  )
)

report_targets <- list(
  tar_render(report, 'report.Rmd')
  #tar_quarto(report, here::here("Reports", "report.qmd")
)

list(data_targets,
     smooth_targets,
     cluster_targets,
     map_targets,
     report_targets)

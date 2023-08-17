
# Load Opioid Overdose Deaths from OASIS ----------------------------------

obtain_data <- function(oasis_path, year){
  
  if(!(year %in% 2013:2021)) stop('Data only available for years 2013-2021.')
  
  op <- readxl::read_excel(oasis_path, na = 'N/A',
                           col_types = c(rep('text', 5), rep('numeric', 9))) |>
    dplyr::filter(Geography != 'County Summary') |>
    tidyr::pivot_longer(cols = `2013`:`2021`, 
                        names_to = 'Year', 
                        values_to = 'Deaths') |>
    dplyr::mutate(Year = as.integer(Year)) |>
    dplyr::summarise(dplyr::across(Deaths, ~ sum(.x, na.rm = TRUE)), 
                     .by = c(Geography, Year)) |>
    dplyr::filter(Year == year)
  
  ga <- tigris::counties(state = 'GA', class = "sf")
  
  pop <- lapply(unique(op$Year), 
                \(year) tidycensus::get_acs(state = 'GA', 
                                            geography = "county", 
                                            year = year,
                                            variables = c("B01003_001")) |>
                          dplyr::mutate(Year = year)) |>
    dplyr::bind_rows()
  
  opga <- op |>
    dplyr::mutate(ID = dplyr::row_number()) |>
    dplyr::left_join(ga, 
                     by = dplyr::join_by('Geography' == 'NAME')) |>
    dplyr::left_join(dplyr::select(pop, GEOID, Year, pop = estimate), 
                     by = c('GEOID', 'Year'))
  
  return(opga)
}


# op <- readxl::read_excel(oasis_path, na = 'N/A',
#                          col_types = c(rep('text', 5), rep('numeric', 9))) |>
#   filter(Geography != 'County Summary') |>
#   pivot_longer(cols = `2013`:`2021`, 
#                names_to = 'Year', 
#                values_to = 'Deaths') |>
#   mutate(Year = as.integer(Year)) |>
#   summarise(across(Deaths, ~ sum(.x, na.rm = TRUE)), 
#             .by = c(Geography, Year)) |>
#   filter(Year == year)
# 
# # Load Georgia Shapefile from Tigris --------------------------------------
# ga <- readr::read_rds(here::here('Data','Raw','ga_county.rds'))
# # ga <- tigris::counties(state = 'GA', class = "sf")
# # write_rds(ga, here::here('Data','Raw','Geography','ga_county.rds'))
# 
# # Load Population Data for Georgia Counties -------------------------------
# # tidycensus::census_api_key("82bc0c32623ce65eff9f6bd0e00aed64ebf21d58")
# 
# pop <- lapply(unique(op$Year), 
#               \(year) tidycensus::get_acs(state = 'GA', 
#                                           geography = "county", 
#                                           year = year,
#                                           variables = c("B01003_001")) |>
#                 mutate(Year = year)) |>
#   bind_rows()
# 
# # write_csv(pop, here::here('Data','Raw','pop.csv'))
# 
# # Combine Data Sources ----------------------------------------------------
# opga <- op |>
#   left_join(ga, by = join_by('Geography' == 'NAME')) |>
#   left_join(select(pop, GEOID, Year, pop = estimate), by = c('GEOID', 'Year'))
# 
# write_rds(opga, here::here('Data','Clean','opga.rds'))


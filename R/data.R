library(tidyverse)

# Load Opioid Overdose Deaths from OASIS ----------------------------------
op <- readxl::read_excel(here::here('Data','Raw','oasis_opioids.xlsx'),
                         na = 'N/A',
                         col_types = c(rep('text', 5), rep('numeric', 9))) |>
  filter(Geography != 'County Summary') |>
  pivot_longer(cols = `2013`:`2021`, names_to = 'Year', values_to = 'Deaths') |>
  mutate(Year = as.integer(Year)) |>
  summarise(across(Deaths, ~ sum(.x, na.rm = TRUE)), .by = c(Geography, Year)) |>
  filter(Year == 2021)


# Load Georgia Shapefile from Tigris --------------------------------------
ga <- tigris::counties(state = 'GA', class = "sf")
# write_rds(ga, here::here('Data','Raw','Geography','ga_county.rds'))

# Load Population Data for Georgia Counties -------------------------------
# tidycensus::census_api_key("82bc0c32623ce65eff9f6bd0e00aed64ebf21d58")

pop <- lapply(unique(op$Year), 
              \(year) tidycensus::get_acs(state = 'GA', 
                                          geography = "county", 
                                          year = year,
                                          variables = c("B01003_001")) |>
                mutate(Year = year)) |>
  bind_rows()

# write_csv(pop, here::here('Data','Raw','pop.csv'))

# Combine Data Sources ----------------------------------------------------
opga <- op |>
  left_join(ga, by = join_by('Geography' == 'NAME')) |>
  left_join(select(pop, GEOID, Year, pop = estimate), by = c('GEOID', 'Year'))

write_rds(opga, here::here('Data','Clean','opga.rds'))


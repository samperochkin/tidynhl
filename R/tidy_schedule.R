#' Get a tidy dataset of the NHL schedule
#'
#' The function `tidy_schedule()` is meant to be a user-friendly way of getting the NHL schedule, including the final score of completed games.
#'
#' @param seasons_id Character vector of the seasons ID for which the schedule will be returned. The required format is 'xxxxyyyy'.
#' @param regular *(optional)* Logical indicating if the regular season schedule should be returned. Default to `TRUE`.
#' @param playoffs *(optional)* Logical indicating if the playoffs schedule should be returned. Default to `TRUE`.
#' @param tz *(optional)* Character specifying the timezone that should be used for datetime. Default to the user system timezone.
#' @param keep_id *(optional)* Logical indicating if the IDs of different dimensions should be returned. Default to `FALSE`.
#' @param return_datatable *(optional)* Logical indicating whether or not a data.table should be returned. Default to `TRUE` if the `data.table` package is
#'   attached in the active session.
#'
#' @examples
#' # Load the data.table package to easily manipulate the data
#' library(data.table)
#'
#' # Get the schedule of the 2019-2020 regular season and playoffs
#' schedule_20192020 <- tidy_schedule("20192020")
#'
#' # Print the column names
#' colnames(schedule_20192020)
#'
#' # Print an excerpt of the data
#' schedule_20192020[, .(season_type, game_datetime, away_team, away_score, home_score, home_team)]
#'
#' # Get the regular season schedule of both the 2018-2019 and 2019-2020 seasons,
#' # keeping the IDs and indicating game datetime with Los Angeles local time
#' schedule_regular_20182020 <- tidy_schedule(
#'   seasons_id = c("20182019", "20192020"),
#'   playoffs   = FALSE,
#'   tz         = "America/Los_Angeles",
#'   keep_id    = TRUE
#' )
#'
#' # Print the column names
#' colnames(schedule_regular_20182020)
#'
#' # Print an excerpt of the data
#' schedule_regular_20182020[, .(season_years, game_id, game_datetime, away_team, home_team)]
#'
#' @export
tidy_schedule <- function(seasons_id, regular=TRUE, playoffs=TRUE, tz=Sys.timezone(), keep_id=FALSE, return_datatable=NULL) {

  check_seasons_id <- seasons_id%in%seasons_info[, season_id]
  if (sum(!check_seasons_id)>0) {
    stop(paste("the following values are invalid for parameter 'seasons_id':", paste(seasons_id[!check_seasons_id], collapse = ", ")))
  }

  if (is.null(return_datatable)) {
    return_datatable <- "data.table"%in%.packages()
  }

  # TO DO: Add more complete parameters check

  games <- rbindlist(lapply(seasons_id, function(id) {

    Sys.sleep(runif(1, 1, 2))

    start <- seasons_info[season_id==id, as.character(season_regular_start)]
    end <- seasons_info[season_id==id, as.character(season_playoffs_end)]

    url <- paste0(api_url, "schedule?startDate=", start, "&endDate=", end, "&expand=schedule.linescore")
    schedule <- jsonlite::fromJSON(httr::content(httr::GET(url), "text"), flatten=TRUE)$dates %>%
      create_data_table()

    games <- rbindlist(schedule[, games], fill=TRUE)

    if (!"season" %in% colnames(games)) {
      games[, season:=NA_character_]
    }
    if (!"gamePk" %in% colnames(games)) {
      games[, gamePk:=NA_integer_]
    }
    if (!"gameType" %in% colnames(games)) {
      games[, gameType:=NA_character_]
    }
    if (!"gameDate" %in% colnames(games)) {
      games[, gameDate:=NA]
    }
    if (!"status.detailedState" %in% colnames(games)) {
      games[, status.detailedState:=NA_character_]
    }
    if (!"venue.name" %in% colnames(games)) {
      games[, venue.name:=NA_character_]
    }
    if (!"teams.away.team.id" %in% colnames(games)) {
      games[, teams.away.team.id:=NA_integer_]
    }
    if (!"teams.home.team.id" %in% colnames(games)) {
      games[, teams.home.team.id:=NA_integer_]
    }
    if (!"linescore.teams.away.goals" %in% colnames(games)) {
      games[, linescore.teams.away.goals:=NA_integer_]
    }
    if (!"linescore.teams.home.goals" %in% colnames(games)) {
      games[, linescore.teams.home.goals:=NA_integer_]
    }
    if (!"linescore.currentPeriod" %in% colnames(games)) {
      games[, linescore.currentPeriod:=NA_integer_]
    }
    if (!"linescore.hasShootout" %in% colnames(games)) {
      games[, linescore.hasShootout:=NA]
    }

    games[gameType%in%c("R", "P"), .(
      season_id = season,
      season_years = season_years(season),
      season_type = ifelse(stringr::str_sub(gamePk, 5L, 6L)=="02", "regular", "playoffs"),
      game_id = gamePk,
      game_datetime = suppressMessages(lubridate::as_datetime(gameDate, tz=tz)),
      game_status = tolower(status.detailedState),
      venue_name = venue.name,
      away_id = teams.away.team.id,
      home_id = teams.home.team.id,
      away_score = linescore.teams.away.goals,
      home_score = linescore.teams.home.goals,
      game_nbot = linescore.currentPeriod-linescore.hasShootout-3L,
      game_shootout = linescore.hasShootout
    )]

  }))

  # TO DO: Make a patch for the missing games, making sure not to duplicate them when the API will be fixed

  games[teams_info, away_team:=team_abbreviation, on=c(away_id="team_id")]
  games[teams_info, home_team:=team_abbreviation, on=c(home_id="team_id")]

  games[game_status!="final", `:=`(
    away_score = NA_integer_,
    home_score = NA_integer_,
    game_nbot = NA_integer_,
    game_shootout = NA
  )]

  setcolorder(games, c("season_id", "season_years", "season_type", "game_id", "game_datetime", "game_status", "venue_name", "away_id", "away_team",
                       "away_score", "home_score", "home_team", "home_id", "game_nbot", "game_shootout"))

  if (!regular) {
    games <- games[season_type!="regular"]
  }

  if (!playoffs) {
    games <- games[season_type!="playoffs"]
  }

  if (!keep_id) {
    games[, colnames(games)[grep("_id$", colnames(games))]:=NULL]
  }

  if (return_datatable) {
    games[]
  } else {
    as.data.frame(games)
  }

}

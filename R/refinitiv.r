# create helper function to check if conda is installed
CondaExists <- function(){

  out <- tryCatch(
    {
      suppressWarnings(suppressMessages(reticulate::conda_binary()))
    },
    error = function(cond) {
      message(paste("Conda does not seem to be installed"))
      message(cond)
      return(FALSE)
    }
  )
  out <- ifelse(isFALSE(out), yes = FALSE, no = TRUE)

  return(out)
}


#' Check if Conda exists, if not instals miniconda, add the python eikon module to the python environment r-reticulate
#'
#' This function can also be used to update the required python packages so that you can always use the latest version of the pyhton packages numpy and eikon.
#'
#' @param method Installation method. By default, "auto" automatically finds a method that will work in the local environment. Change the default to force a specific installation method. Note that the "virtualenv" method is not available on Windows.
#' @param conda  The path to a conda executable. Use "auto" to allow reticulate to automatically find an appropriate conda binary. See Finding Conda in the reticulate package for more details
#' @param envname the name for the conda environment that will be used, default  r-reticulate. Don't Change!
#' @param update boolean, allow to rerun the command to update the packages required to update the python packages numpy and eikon defaults to true
#'
#' @return None
#' @importFrom utils installed.packages
#' @export
#'
#' @examples
#' \dontrun{
#' install_eikon()
#' }
install_eikon <- function(method = "auto", conda = "auto", envname= "r-reticulate", update = TRUE) {

# Check if a conda environment exists and install if not available
  if (CondaExists() == FALSE ) {
      message("installing MiniConda, if this fails retry by running r/rstudio with windows administrative powers/linux elevated permissions")
      reticulate::install_miniconda(update = TRUE, force = TRUE)
      message('Miniconda installed')

  }
 if (!(envname %in% reticulate::conda_list()$name)) {
     reticulate::conda_create(envname = envname )
    }

  # reticulate::use_condaenv(condaenv = envname, conda = conda)

  if (!reticulate::py_module_available("eikon") || update ) {
      reticulate::py_install(packages = c("numpy", "eikon") , envname = envname,  method = method, conda = conda, pip = TRUE)
  }

  return("Eikon Python interface successfully installed or updated")
}



#Data stream r api------------------

#' Initialize DataStream Connection
#'
#' @param DatastreamUserName Refinitiv DataStream username
#' @param DatastreamPassword Refinitiv DataStream password
#'
#' @return a DataStream R5 object
#' @export
#'
#' @examples
#' \dontrun{
#' DatastreamUserName <- "Your datastream username"
#' DatastreamPassword <- "Your datastream password"
#' DataStream <- DataStreamConnect(DatastreamUserName, DatastreamPassword)
#' }
DataStreamConnect <- function(DatastreamUserName, DatastreamPassword){

  options(Datastream.Username = DatastreamUserName)
  options(Datastream.Password = DatastreamPassword)
  mydsws <- DatastreamDSWS2R::dsws$new()
  return(mydsws)

  }

# Initialize eikon Python api using reticulate -------------------------------

#' Initialize Eikon Python api
#'
#' @param Eikonapplication_port proxy port id
#' @param Eikonapplication_id eikon api key
#'
#' @return a Python module that is an EikonObject
#' @export
#'
#' @examples
#' \dontrun{
#' Eikon <- EikonConnect(Eikonapplication_id = "your key", Eikonapplication_port = 9000L)
#' }
EikonConnect <- function(Eikonapplication_id = getOption(".EikonApiKey") , Eikonapplication_port = 9000L) {

  options(.EikonApiKey = Eikonapplication_id)
  options(.EikonApplicationPort = Eikonapplication_port)

  reticulate::use_condaenv(condaenv = "r-reticulate", conda = "auto") # set virtual environment right
  PythonEK <- reticulate::import(module = "eikon") # import python eikon module

  PythonEK$set_port_number(.Options$.EikonApplicationPort)
  PythonEK$set_app_key(app_key = .Options$.EikonApiKey)

  return(PythonEK)
}


#' Show the attributes of the Python Eikon
#'
#' Function that the returns the names of the python Eikon api attributes that can be used as commands in R.
#'
#' @param EikonObject Python Object generated by EikonConnect
#'
#' @return a list of attributes
#' @export
#'
#' @examples
#' \dontrun{
#' Eikon <- EikonConnect(Eikonapplication_id = "your key", Eikonapplication_port = 9000L)
#' EikonShowAttributes(EikonObject = Eikon)
#' }
EikonShowAttributes <- function(EikonObject){
  PossibleAttributes <- reticulate::py_list_attributes(EikonObject)
  return(PossibleAttributes)
  }




#' Convert eikon formula's in human readable names
#'
#' @param names vector of data.frame column names
#'
#' @return a data.frame in which the Eikon formula's are replaced with the Eikon display Name which is the last part of the formula.
#' @export
#'
#' @examples
EikonNameCleaner <- function(names){

  returnNames <-  lapply( names
                        , FUN = function(x){TryCleanName <- unlist(qdapRegex::rm_between(x, '/*', '*/', extract = TRUE));
                                            return(ifelse(test = !is.na(TryCleanName), yes = TryCleanName, no = x ))
                                           }

                        )
  #replace spaces with "." to have better data.frame columnnames
  returnNames <- gsub(x = returnNames, pattern = " ", replacement = ".")
  returnNames <- stringi::stri_trans_general(returnNames, "latin-ascii")

  return(returnNames)
}



#' Returns a list of chunked Rics so that api limits can be satisfied
#'
#' @param RICS a vector containing RICS to be requested
#' @param Eikonfields a list of the eikonfields to be requested default NULL, if eikonfields are supplied duration may not be supplied
#' @param MaxCallsPerChunk the maximum amount of apicalls that can be made
#' @param Duration a natural number denoting the amoount of rows asked for in a TimeSeries default NULL, if Duration is supplied Eikonfields may not be supplied
#' @param MaxRicsperChunk  a natural number denoting the maximum amount of Rics that should be available in one call, default is 300.
#'
#' @return a list of splitted RICS that can be returned to guarantee compliance with api limits.
#' @export
#' @references \url{https://developers.refinitiv.com/eikon-apis/eikon-data-api/docs?content=49692&type=documentation_item}
#'
#' @examples
EikonChunker <- function(RICS, Eikonfields = NULL, MaxCallsPerChunk = 12000, Duration = NULL, MaxRicsperChunk = 300) {

  if (!is.null(Eikonfields) & is.null(Duration)) {
    totalDataPoints <- length(RICS) * length(Eikonfields)
  } else if (!is.null(Duration) & is.null(Eikonfields)) {
    totalDataPoints <- length(RICS) * Duration
    if (Duration > MaxCallsPerChunk) {
        stop("Duration is too long for even one RIC, Reduce Duration by changing start_date or end_date!")
    }
  } else{
      stop("supply either Duration or Eikonfields")
  }


  # # Make sure that api limits are respected

  message(paste0("the operation you intend to perform will cost ", totalDataPoints, " data points"))
  Chunks <- ceiling(totalDataPoints/MaxCallsPerChunk)
  ChunkLength <- length(RICS)/Chunks

  # ChosenSimulataneousRics <- length(Stoxx1800Constits$RIC)/chosenchunks
  if(!is.null(MaxRicsperChunk)){
    if(ChunkLength > MaxRicsperChunk){
      ChunkLength <- MaxRicsperChunk - 1
    }
  }

  SplittedRics <-  split(RICS, ceiling(seq_along(RICS)/ChunkLength))
  return(SplittedRics)
}


#' Function to retry failed functions after a time out of 5 seconds. Especially useful for failed api calls.
#'
#' @param max maximum number of retries, default = 2
#' @param init initial state of retries should always be left zero, default = zero
#' @param retryfun function to retry.
#'
#' @return None
#' @export
#'
#' @examples  retry(sum(1,"a"), max = 2)
retry <- function(retryfun, max = 2, init = 0){
  suppressWarnings( tryCatch({
    if (init < max) retryfun
  }, error = function(e){message(paste0("api request failed, automatically retrying time ",init + 1, "/", max))
                        ; Sys.sleep(time = 5); retry(retryfun, max, init = init + 1);return(NA)}))
}


#' Function to obtain timeseries from Eikon. Based on the Eikon python function get_timeseries
#'
#' Automatically chunks the timeseries in seperate apicalls and binds them together again in order to comply with api regulations.
#'
#' @param EikonObject Python eikon module result from EikonConnect
#' @param rics a vector containing Reuters rics
#' @param interval Data interval. Possible values: 'tick', 'minute', 'hour', 'daily', 'weekly', 'monthly', 'quarterly', 'yearly'  Default: 'daily'
#' @param calender Possible values: 'native', 'tradingdays', 'calendardays'., Default: 'tradingdays'
#' @param fields a vector containing  any combination ('TIMESTAMP', 'VOLUME', 'HIGH', 'LOW', 'OPEN', 'CLOSE')
#' @param start_date Starting date and time of the historical range. string format is: '\%Y-\%m-\%dT\%H:\%M:\%S'.
#' @param end_date  End date and time of the historical range.  string format is: '\%Y-\%m-\%dT\%H:\%M:\%S'.
#' @param cast  cast data from wide to long format using the data.table::dcast function, Default: TRUE
#' @param time_out set the maximum timeout to the Eikon server, default = 60
#' @param verbose boolean if TRUE prints out the python call to the console
#'
#' @return A data.frame containing time series from Eikon
#' @export
#'
#' @references \url{https://developers.refinitiv.com/eikon-apis/eikon-data-api/docs?content=49692&type=documentation_item}
#' @importFrom  data.table rbindlist dcast
#' @examples
#' \dontrun{
#' Eikon <- Refinitiv::EikonConnect()
#' EikonGetTimeseries(EikonObject = Eikon, rics = c("MMM", "III.L"),
#'                    start_date = "2020-01-01T01:00:00",
#'                    end_date = paste0(Sys.Date(), "T01:00:00"), verbose = TRUE)
#' }
EikonGetTimeseries <- function(EikonObject, rics, interval = "daily", calender = "tradingdays", fields = c('TIMESTAMP', 'VOLUME', 'HIGH', 'LOW', 'OPEN', 'CLOSE')
                              , start_date = "2020-01-01T01:00:00", end_date = paste0(Sys.Date(), "T01:00:00"), cast = TRUE, time_out = 60, verbose = FALSE){

  # Make sure that Python object has api key and change timeout
  EikonObject$set_timeout(timeout = time_out)
  EikonObject$set_app_key(app_key = .Options$.EikonApiKey)





  # Convert as posix
  start_date <- as.POSIXct(start_date, format = "%Y-%m-%dT%H:%M:%S")
  end_date <- as.POSIXlt(end_date, format = "%Y-%m-%dT%H:%M:%S")

  # Build dataframe for internal lookup of names and datapoints limits
  difftimeConversionTable <- data.frame( EikonTimeName = c('tick', 'minute', 'hour', 'daily', 'weekly', 'monthly', 'quarterly', 'yearly')
                                       , difftimeName = c(NA,  "mins", "hours","days", "weeks", NA, NA, NA)
                                       , limit = c(50000,50000,50000,3000,3000,3000,3000,3000)
                                       , stringsAsFactors = FALSE
                                       )


  #check if chunking is required
  # CalculateDuration based on weekends
  if (interval %in% c('tick')) {
    warning("Intraday tick data chunking currently not supported, maximum 50.000 data points per request")
  } else if ( interval %in% c('minute', 'hour', 'daily', 'weekly')) {
    Duration <- difftime(end_date, start_date
                        , units = difftimeConversionTable[difftimeConversionTable$EikonTimeName == interval,]$difftimeName
                        )[[1]]
    # remove weekends as these need not be to downloaded, public holidays ignored
    Duration <- Duration/7*5
  } else if (interval == "monthly") {
    Duration <- (zoo::as.yearmon(end_date) - zoo::as.yearmon(start_date))*12
  } else if (interval == "quarterly") {
    Duration <- (zoo::as.yearqtr(end_date) - zoo::as.yearqtr(start_date))*4
  } else if (interval == "yearly") {
    Duration <- difftime(end_date, start_date, units = "days")[[1]]
    Duration <- as.double(Duration)/365 # absolute years
  }

 # Now calculate amount of datapoints, these are calculated as used rows

  if (!is.null(Duration)) {
    Datapoints <- ceiling(Duration) * length(rics)
    Limit <- difftimeConversionTable[difftimeConversionTable$EikonTimeName == interval,]$limit
  }

  if ( !is.null(Duration) && (Limit < Datapoints)) {
    message("The operation is too large for one api request and will be chunked in multiple requests")
    ChunckedRics <- EikonChunker(RICS = rics, MaxCallsPerChunk = Limit, Duration =  ceiling(Duration), MaxRicsperChunk = 300 )
  } else{
    ChunckedRics <- list(rics)
  }


  TimeSeriesList <- as.list(rep(NA, times = length(ChunckedRics)))
  for (j in 1:length(ChunckedRics)) {
    TimeSeriesList[[j]] <- try({ if (verbose){  message(paste0(Sys.time(), "\n"
                                                               , " get_timeseries( rics = [\"", paste(ChunckedRics[[j]], collapse = "\",\""), "\"]\n"
                                                               , "\t, interval= \"", interval, "\"\n"
                                                               , "\t, interval= \"", calender, "\"\n"
                                                               , "\t, fields = [\"", paste(fields, collapse = "\",\""),  "\"]\n"
                                                               , "\t, start_date =  \"", as.character(start_date,  "%Y-%m-%dT%H:%M:%S"), "\"\n"
                                                               , "\t, end_date =  \"", as.character(end_date,  "%Y-%m-%dT%H:%M:%S"), "\"\n"
                                                               , "\t, normalize = False\n\t)"
    )
    )}




      retry(EikonObject$get_timeseries( rics = ChunckedRics[[j]]
                                                               , interval = interval
                                                               , calendar = calender
                                                               , fields = fields
                                                               , start_date = as.character(start_date,  "%Y-%m-%dT%H:%M:%S")
                                                               , end_date = as.character(end_date,  "%Y-%m-%dT%H:%M:%S")
                                                               , normalize = TRUE
                                                               )

    )})
    CheckandReportEmptyDF(df = TimeSeriesList[[j]], functionname = "EikonGetTimeseries")
    Sys.sleep(time = 0.5)
  }

  # ReturnTimeSeries <- do.call("rbind", TimeSeriesList)
  TimeSeriesList <- lapply(TimeSeriesList, FUN = function(x){if(all(is.na(x))){return(NULL)} else{return(x)}})

  ReturnTimeSeries <- data.table::rbindlist(TimeSeriesList, use.names = TRUE, fill = TRUE)
  ReturnTimeSeries <- make.true.NA_df(ReturnTimeSeries)
  ReturnTimeSeries <- data.table::as.data.table(ReturnTimeSeries)

  if ((isTRUE(cast) & !all(is.na(ReturnTimeSeries))) && (nrow(ReturnTimeSeries) > 0) ) {
    # ReturnTimeSeries <- reshape2::dcast(unique(ReturnTimeSeries),  Date + Security ~ Field, fill = NA_integer_, drop = FALSE, value.var = "Value")
    ReturnTimeSeries <- data.table::dcast(unique(ReturnTimeSeries),  Date + Security ~ Field, fill = NA_integer_, drop = FALSE, value.var = "Value")
    ReturnTimeSeries <- ReturnTimeSeries[order(ReturnTimeSeries$Security),]


   }
  ReturnTimeSeries <- as.data.frame(ReturnTimeSeries, stringsAsFactors = FALSE) #remove dcast class as it has no use.
  return(ReturnTimeSeries)
}





#' Function to obtain data from Eikon. Based on the Eikon python function get_data
#'
#' The function automatically chunks the list of rics into chunks that comply with the api limitations and in the end rebuilds the chunks again into a single data.frame.
#'
#' @param EikonObject Eikon object created using EikonConnect function
#' @param rics a vector containing the instrument RICS
#' @param Eikonformulas a vector containing character string of Eikon Formulas
#' @param Parameters a named key value list for setting parameters, Default: NULL
#' @param raw_output to return the raw list by chunk for debugging purposes, default = FALSE
#' @param time_out set the maximum timeout to the Eikon server, default = 60
#' @param verbose boolean, set to true to print out the actual python call with time stamp for debugging.
#'
#' @return a data.frame containing data.from Eikon
#' @export
#' @references \url{https://developers.refinitiv.com/eikon-apis/eikon-data-api/docs?content=49692&type=documentation_item}
#'
#' @examples
#' \dontrun{
#' Eikon <- Refinitiv::EikonConnect()
#' EikonGetData(EikonObject = Eikon, rics = c("MMM", "III.L"),
#'              Eikonformulas = c("TR.PE(Sdate=0D)/*P/E (LTM) - Diluted Excl*/"
#'              , "TR.CompanyName"), verbose = TRUE)
#' }
EikonGetData <- function(EikonObject, rics, Eikonformulas, Parameters = NULL, raw_output = FALSE, time_out = 60, verbose = FALSE){

#Make sure that Python object has api key
EikonObject$set_app_key(app_key = .Options$.EikonApiKey)
EikonObject$set_timeout(timeout = time_out) #add timeout to reduce chance on timeout error chance.


# Divide RICS in chunks to satisfy api limits
ChunckedRics <- Refinitiv::EikonChunker(RICS = rics, Eikonfields = Eikonformulas)


EikonDataList <- as.list(rep(NA, times = length(ChunckedRics)))
for (j in 1:length(ChunckedRics)) {
  EikonDataList[[j]] <- try({ if (verbose){  message(paste0(Sys.time(), "\n"
                                                    , " get_data( instruments = [\"", paste(ChunckedRics[[j]], collapse = "\",\""), "\"]\n"
                                                    , "\t, fields = [\"", paste(Eikonformulas, collapse = "\",\""),  "\"]\n"
                                                    , "\t, debug = False, raw_output = False\n\t)"
                                                    )
                                                    )}
                             retry(EikonObject$get_data( instruments = ChunckedRics[[j]]
                                           , fields = as.list(Eikonformulas)
                                           , parameters = Parameters
                                           , debug = FALSE, raw_output = FALSE
  ), max = 3)})



  CheckandReportEmptyDF(df = EikonDataList[[j]], functionname = "EikonGetData")
  Sys.sleep(time = 0.5)
}


if (!raw_output) {
  EikonDataList <- lapply(EikonDataList, FUN = function(x){if(all(is.na(x))){return(NULL)} else{return(x)}})
  ReturnElement <- EikonPostProcessor(EikonDataList)
} else {
  ReturnElement <- EikonDataList
}

return(ReturnElement)
}







# #' @param debug boolean When set to TRUE, the json request and response are printed.



#' Returns a list of instrument names converted into another instrument code.
#' For example: convert SEDOL instrument names to RIC names
#'
#' original python parameters raw_output and debug cannot be used due to int64 python to R conversion problem.
#' \url{https://github.com/rstudio/reticulate/issues/729}
#'
#' @param EikonObject Eikon object created using EikonConnect function
#' @param symbol character or list of characters 	Single instrument or list of instruments to convert.
#' @param from_symbol_type character Instrument code to convert from. Possible values: 'CUSIP', 'ISIN', 'SEDOL', 'RIC', 'ticker', 'lipperID', 'IMO' Default: 'RIC'
#' @param to_symbol_type character  string or list 	Instrument code to convert to. Possible values: 'CUSIP', 'ISIN', 'SEDOL', 'RIC', 'ticker', 'lipperID', 'IMO', 'OAPermID' Default: None (means all symbol types are requested)
#' @param raw_output boolean 	Set this parameter to True to get the data in json format if set to FALSE, the function will return a data frame Default: FALSE
#' @param bestMatch boolean 	When set to TRUE, only primary symbol is requested. When set to FALSE, all symbols are requested
#' @param time_out numeric set the maximum timeout to the Eikon server, default = 60
#' @param verbose boolean, set to true to print out the actual python call with time stamp for debugging.
#'
#' @return data.frame
#' @export
#'
#' @examples
#' \dontrun{
#' Eikon <- Refinitiv::EikonConnect()
#' ex1 <- EikonGetSymbology(EikonObject = Eikon, symbol =  "AAPL.O"
#'  , to_symbol_type = "ISIN" )
#' ex2 <- EikonGetSymbology(EikonObject = Eikon
#' , symbol =  "GB00B03MLX29", from_symbol_type = "ISIN"
#' ,  to_symbol_type = "RIC" , verbose = TRUE)
#' ex3 <- EikonGetSymbology(EikonObject = Eikon
#' , symbol =  "GB00B03MLX29", from_symbol_type = "ISIN"
#' ,  to_symbol_type = "RIC" , verbose = TRUE, bestMatch = FALSE)
#' ex4 <- EikonGetSymbology(EikonObject = Eikon, symbol =  "RDSa.AS"
#' , to_symbol_type = "ISIN"  , verbose = TRUE)
#' ex5 <- EikonGetSymbology(EikonObject = Eikon, symbol =  "RDSa.L"
#' , to_symbol_type = "ISIN"  , verbose = TRUE)
#' ex6 <- EikonGetSymbology(EikonObject = Eikon
#' , symbol =  c("GB00B03MLX29", "NL0015476987"), from_symbol_type = "ISIN"
#' ,  to_symbol_type = "RIC" , verbose = TRUE, bestMatch = FALSE)
#' ex7 <- EikonGetSymbology(EikonObject = Eikon
#' , symbol =  c("GB00B03MLX29", "US0378331005"), from_symbol_type = "ISIN"
#' ,  to_symbol_type = "RIC" , verbose = TRUE, bestMatch = FALSE)
#' }
EikonGetSymbology <- function( EikonObject, symbol, from_symbol_type = "RIC", to_symbol_type = c('CUSIP', 'ISIN', 'SEDOL', 'RIC', 'ticker', 'lipperID', 'IMO', 'OAPermID')
                               , bestMatch = TRUE, time_out = 60, verbose = FALSE, raw_output = TRUE){

  #Make sure that Python object has api key
  EikonObject$set_app_key(app_key = .Options$.EikonApiKey)
  EikonObject$set_timeout(timeout = time_out) #add timeout to reduce chance on timeout error chance.


  # Divide symbols in chunks to satisfy api limits
  ChunckedSymbols <- Refinitiv::EikonChunker(RICS = symbol, Eikonfields = to_symbol_type)

  EikonSymbologyList <- as.list(rep(NA, times = length(ChunckedSymbols)))
  for (j in 1:length(ChunckedSymbols)) {
    EikonSymbologyList[[j]] <- try({ if (verbose){  message(paste0(Sys.time(), "\n"
                                                              , "get_symbology( symbol = [\"", paste(ChunckedSymbols[[j]], collapse = "\",\""), "\"]\n"
                                                              , "\t, from_symbol_type = [\"", paste(from_symbol_type, collapse = "\",\""),  "\"]\n"
                                                              , "\t, to_symbol_type = [\"", paste(to_symbol_type, collapse = "\",\""),  "\"]\n"
                                                              , "\t, bestMatch = ", ifelse(test = isTRUE(bestMatch), yes = "True", no = "False")  ,"\n"
                                                              , "\t, debug = False, raw_output = True\n\t)"
    )
    )}
      retry(EikonObject$get_symbology( symbol = ChunckedSymbols[[j]]
                                     , from_symbol_type = from_symbol_type
                                     , to_symbol_type = list(to_symbol_type)
                                     , raw_output = TRUE
                                     , debug = FALSE
                                     , bestMatch = bestMatch
                                  ))
    })
    CheckandReportEmptyDF(df = EikonSymbologyList[[j]], functionname = "EikonGetSymbology")
    Sys.sleep(time = 0.5)
  }


  if (!raw_output) {
     EikonSymbologyList <- lapply(EikonSymbologyList, FUN = function(x){if(all(is.na(x))){return(NULL)} else{return(x)}})
     ReturnElement <- ProcessSymbology(EikonSymbologyList, from_symbol_type = from_symbol_type, to_symbol_type = to_symbol_type)
   } else {
     ReturnElement <- EikonSymbologyList
   }

  return(ReturnElement)
}




#' function to check if a downloaded dataframe is empty
#'
#' @param df data.frame
#' @param functionname functionname for errorreporting
#'
#' @return boolean
#' @export
#'
#' @examples
#' CheckandReportEmptyDF(data.frame(), functionname = "test")
#' CheckandReportEmptyDF(data.frame(test = c(1,2),test2 = c("a","b")), functionname = "test")
CheckandReportEmptyDF <- function(df, functionname){

if(!all(is.data.frame(df)) && all(is.na(df))){
  df <- NULL
}

if(!is.data.frame(df) && is.list(df)){
  df <- df[[1]]
}

if(is.null(df) || !is.data.frame(df) || nrow(df) == 0 ){
  message(paste0(functionname, " request returned empty dataframe"))
  return(FALSE)
} else{
  return(TRUE)
}

}





# getQuote should function like getSymbols
# getQuote.yahoo
# getQuote.IBrokers
# getQuote.RBloomberg
# getQuote.OpenTick

`getQuote` <-
function(Symbols,src='yahoo',what, ...) {
  args <- list(Symbols=Symbols,...)
  if(!missing(what))
      args$what <- what
  do.call(paste('getQuote',src,sep='.'), args)
}

`getQuote.yahoo` <-
function(Symbols,what=standardQuote(),...) {
  tmp <- tempfile()
  on.exit(unlink(tmp))
  if(length(Symbols) > 1 && is.character(Symbols))
    Symbols <- paste(Symbols,collapse=";")
  length.of.symbols <- length(unlist(strsplit(Symbols, ";")))
  if(length.of.symbols > 200) {
    # yahoo only works with 200 symbols or less per call
    # we will recursively call getQuote.yahoo to handle each block of 200
    Symbols <- unlist(strsplit(Symbols,";"))
    all.symbols <- lapply(seq(1,length.of.symbols,200),
                          function(x) na.omit(Symbols[x:(x+199)]))
    df <- NULL
    cat("downloading set: ")
    for(i in 1:length(all.symbols)) {
      Sys.sleep(0.5)
      cat(i,", ")
      df <- rbind(df, getQuote.yahoo(all.symbols[[i]],what))
    }
    cat("...done\n")
    return(df)
  }
  Symbols <- paste(strsplit(Symbols,';')[[1]],collapse=',')
  if(inherits(what, 'quoteFormat')) {
    QF <- what[[1]]
    QF.names <- what[[2]]
  } else {
    QF <- what
    QF.names <- NULL
  }
  # JSON API currently returns the following fields with every request:
  # language, quoteType, regularMarketTime, marketState, exchangeDataDelayedBy,
  # exchange, fullExchangeName, market, sourceInterval, exchangeTimezoneName,
  # exchangeTimezoneShortName, gmtOffSetMilliseconds, tradeable, symbol
  QFc <- paste0(QF,collapse=',')
  download.file(paste0(
                "https://query1.finance.yahoo.com/v7/finance/quote?symbols=",
                Symbols,
                "&fields=",QFc),
                destfile=tmp,quiet=TRUE)
  # The 'response' data.frame has fields in columns and symbols in rows
  response <- jsonlite::fromJSON(tmp)
  if (is.null(response$quoteResponse$error)) {
    sq <- response$quoteResponse$result
  } else {
    stop(response$quoteResponse$error)
  }
  # Always return symbol and time
  # Use exchange TZ, if possible. POSIXct must have only one TZ, so times
  # from different timezones will be converted to a common TZ
  tz <- sq[, "exchangeTimezoneName"]
  if (length(unique(tz)) == 1L) {
    Qposix <- .POSIXct(sq[,"regularMarketTime"], tz=tz[1L])
  } else {
    warning("symbols have different timezones; converting to local time")
    convertTZ <- function(x) {
      tz <- x$exchangeTimezoneName[1]
      times <- .POSIXct(x$regularMarketTime, tz)
      attr(times, "tzone") <- NULL
      times
    }
    Qposix <- sapply(split(sq, sq$exchangeTimezoneName), convertTZ)
    Qposix <- .POSIXct(Qposix, tz=NULL)  # force local timezone
  }

  Symbols <- unlist(strsplit(Symbols,','))
  df <- data.frame(Qposix, sq[,QF])
  rownames(df) <- Symbols
  if(!is.null(QF.names)) {
    colnames(df) <- c('Trade Time',QF.names)
  }
  df
}


# integrate this into the main getQuote.yahoo, after branching that
#
`getAllQuotes` <-
function() {
st <- seq(1,3000,200)
en <- seq(200,3000,200)
aq <- NULL
for(i in 1:length(st)) {
  cc <- getQuote(paste(read.csv(options()$symbolNamesFile.NASDAQ, sep='|')$Sym[seq(st[i],en[i])],collapse=';'))
  cat('finished first',en[i],'\n')
  Sys.sleep(.1)
  aq <- rbind(aq,cc)
}
aq
}


`standardQuote` <- function(src='yahoo') {
  do.call(paste('standardQuote',src,sep='.'),list())
}

`standardQuote.yahoo` <- function() {
   yahooQF(names=c("Last Trade (Price Only)",
                   "Change","Change in Percent",
                   "Open", "Days High", "Days Low", "Volume"))
}

yahooQuote.EOD <- structure(list("ohgl1v", c("Open", "High",
                                   "Low", "Close",
                                   "Volume")), class="quoteFormat")

`yahooQF` <- function(names) {
  optnames <- .yahooQuoteFields[,"name"]
  optshort <- .yahooQuoteFields[,"shortname"]
  optcodes <- .yahooQuoteFields[,"field"]

  w <- NULL

  if(!missing(names)) {
    names <- unlist(strsplit(names,';'))
    for(n in names) {
      w <- c(w,which(optnames %in% n))
    }
  } else {
    names <- select.list(optnames, multiple=TRUE)
    for(n in names) {
      w <- c(w,which(optnames %in% n))
    }
  }
  return(structure(list(optcodes[w], optshort[w]), class='quoteFormat'))
}

.yahooQuoteFields <-
matrix(c(
  # quote / symbol
  "Symbol", "Symbol", "symbol",
  "Name", "Name", "shortName",
  "Name (Long)", "NameLong", "longName",
  "Quote Type", "Quote Type", "quoteType",
  "Quote Source Name", "Quote Source", "quoteSourceName",
  "Source Interval", "Source Interval", "sourceInterval",
  "Currency", "Currency", "currency",
  "Financial Currency", "Financial Currency", "financialCurrency",

  # market / exchange
  "Market", "Market", "market",
  "Market State", "Market State", "marketState",
  "Exchange", "Exchange", "exchange",
  "Exchange Full Name", "Exchange Full Name", "fullExchangeName",
  "Exchange Timezone", "Exchange Timezone", "exchangeTimezoneName",
  "Exchange TZ", "Exchange TZ", "exchangeTimezoneShortName",
  "Exchange Data Delay", "Exchange Data Delay", "exchangeDataDelayedBy",
  "GMT Offset Millis", "GMT Offset", "gmtOffSetMilliseconds",
  "Tradeable", "Tradeable", "tradeable",

  # market data
  "Ask", "Ask", "ask",
  "Bid", "Bid", "bid",
  "Ask Size", "Ask Size", "askSize",
  "Bid Size", "Bid Size", "bidSize",
  "Last Trade (Price Only)", "Last", "regularMarketPrice",
  "Last Trade Time", "Last Trade Time", "regularMarketTime",
  "Change", "Change", "regularMarketChange",
  "Open", "Open", "regularMarketOpen",
  "Days High", "High", "regularMarketDayHigh",
  "Days Low", "Low", "regularMarketDayLow",
  "Volume", "Volume", "regularMarketVolume",
  "Change in Percent", "% Change", "regularMarketChangePercent",
  "Previous Close", "P. Close", "regularMarketPreviousClose",
  #"Trade Date", "Trade Date", "d2",
  #"Last Trade Size", "Last Size", "k3",
  #"Last Trade (Real-time) With Time", "Last Trade (RT) With Time", "k1",
  #"Last Trade (With Time)", "Last", "l",
  #"High Limit", "High Limit", "l2",
  #"Low Limit", "Low Limit", "l3",
  #"Order Book (Real-time)", "Order Book (RT)", "i5",
  #"Days Range", "Days Range", "m",
  #"Days Range (Real-time)", "Days Range (RT)", "m2",
  #"52-week Range", "52-week Range", "w",

  # trading stats
  "Change From 52-week Low", "Change From 52-week Low", "fiftyTwoWeekLowChange",
  "Percent Change From 52-week Low", "% Change From 52-week Low", "fiftyTwoWeekLowChangePercent",
  "Change From 52-week High", "Change From 52-week High", "fiftyTwoWeekHighChange",
  "Percent Change From 52-week High", "% Change From 52-week High", "fiftyTwoWeekHighChangePercent",
  "52-week Low", "52-week Low", "fiftyTwoWeekLow",
  "52-week High", "52-week High", "fiftyTwoWeekHigh",

  "50-day Moving Average", "50-day MA", "fiftyDayAverage",
  "Change From 50-day Moving Average", "Change From 50-day MA", "fiftyDayAverageChange",
  "Percent Change From 50-day Moving Average", "% Change From 50-day MA", "fiftyDayAverageChangePercent",
  "200-day Moving Average", "200-day MA", "twoHundredDayAverage",
  "Change From 200-day Moving Average", "Change From 200-day MA", "twoHundredDayAverageChange",
  "Percent Change From 200-day Moving Average", "% Change From 200-day MA", "twoHundredDayAverageChangePercent",

  # valuation stats
  "Market Capitalization", "Market Capitalization", "marketCap",
  #"Market Cap (Real-time)", "Market Cap (RT)", "j3",
  "P/E Ratio", "P/E Ratio", "trailingPE",
  #"P/E Ratio (Real-time)", "P/E Ratio (RT)", "r2",
  #"Price/EPS Estimate Current Year", "Price/EPS Estimate Current Year", "r6",
  "Price/EPS Estimate Next Year", "Price/EPS Estimate Next Year", "forwardPE",
  "Price/Book", "Price/Book", "priceToBook",
  "Book Value", "Book Value", "bookValue",
  #"Price/Sales", "Price/Sales", "p5",
  #"PEG Ratio", "PEG Ratio", "r5",
  #"EBITDA", "EBITDA", "j4",

  # share stats
  "Average Daily Volume", "Ave. Daily Volume", "averageDailyVolume3Month",
  #"Average Daily Volume", "Ave. Daily Volume", "averageDailyVolume10Day",
  "Shares Outstanding", "Shares Outstanding", "sharesOutstanding",
  #"Float Shares", "Float Shares", "f6",
  #"Short Ratio", "Short Ratio", "s7",

  # dividends / splits
  "Ex-Dividend Date", "Ex-Dividend Date", "dividendDate",
  #"Dividend Pay Date", "Dividend Pay Date", "r1",
  "Dividend/Share", "Dividend/Share", "trailingAnnualDividendRate",
  "Dividend Yield", "Dividend Yield", "trailingAnnualDividendYield",

  # earnings
  "Earnings Timestamp", "Earnings Timestamp", "earningsTimestamp",
  "Earnings Start Time", "Earnings Start Time", "earningsTimestampStart",
  "Earnings End Time", "Earnings End Time", "earningsTimestampEnd",
  "Earnings/Share", "Earnings/Share", "epsTrailingTwelveMonths",
  "EPS Forward", "EPS Forward", "epsForward",
  #"Earnings/Share", "Earnings/Share", "e",
  #"EPS Estimate Current Year", "EPS Estimate Current Year", "e7",
  #"EPS Estimate Next Year", "EPS Estimate Next Year", "e8",
  #"EPS Estimate Next Quarter", "EPS Estimate Next Quarter", "e9",

  # yahoo / meta
  "Language", "Language", "language",
  "Message Board ID", "Message Board ID", "messageBoardId",
  "Price Hint", "Price Hint", "priceHint"

  # user portfolio
  #"Trade Links", "Trade Links", "t6",
  #"Ticker Trend", "Ticker Trend", "t7",
  #"1 yr Target Price", "1 yr Target Price", "t8",
  #"Holdings Value", "Holdings Value", "v1",
  #"Holdings Value (Real-time)", "Holdings Value (RT)", "v7",
  #"Days Value Change", "Days Value Change", "w1",
  #"Days Value Change (Real-time)", "Days Value Change (RT)", "w4",
  #"Price Paid", "Price Paid", "p1",
  #"Shares Owned", "Shares Owned", "s1",
  #"Commission", "Commission", "c3",
  #"Notes", "Notes", "n4",
  #"More Info", "More Info", "i",
  #"Annualized Gain", "Annualized Gain", "g3",
  #"Holdings Gain", "Holdings Gain", "g4",
  #"Holdings Gain Percent", "Holdings Gain %", "g1",
  #"Holdings Gain Percent (Real-time)", "Holdings Gain % (RT)", "g5",
  #"Holdings Gain (Real-time)", "Holdings Gain (RT)", "g6",

  #"Error Indication (returned for symbol changed / invalid)", "Error Indication (returned for symbol changed / invalid)", "e1",
  ),
ncol = 3, byrow = TRUE, dimnames = list(NULL, c("name", "shortname", "field")))

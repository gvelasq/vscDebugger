

#' Modified version of `base::cat()` for vsc
#'
#' Captures the output of `base::cat(...)` and sends it to vsc together with information about the sourcefile and line
#' @export
#' @param ... Arguments passed to base::cat()
#' @param skipCalls The number of calls to skip when reporting the calling file and line. Can be used e.g. inside log functions.
#' @param showSource Whether to show the calling source file and line.
#' @return NULL (invisible)
.vsc.cat <- function(..., skipCalls=0, showSource=TRUE) {
  # TODO: consider correct environment for base::print(...)?
  # env <- sys.frame(-1)
  # ret <- capture.output(base::print(...), envir=env)

  if (session$state$isEvaluatingSilent()) {
    return(base::cat(...))
  }

  split <- session$splitOverwrittenOutput
  args <- list(...)

  if(identical(args$file, stderr())){
    if(split){
      # cannot split message connection -> cat() twice
      base::cat(...)
    }
    category <- 'stderr'
    args['file'] <- NULL
    ret <- capture.output({do.call(base::cat, args);base::cat("\n")})
  } else if(is.null(args$file) || identical(args$file, '')){
    type <- 'output'
    category <- 'stdout'
    ret <- capture.output({do.call(base::cat, args);base::cat("\n")}, type=type, split=split)
  } else{
    return(base::cat(...))
  }

  printToVsc(ret, skipCalls+1, category, showSource = showSource)
  invisible(NULL)
}


#' Modified version of `base::print()` for vsc
#'
#' Captures the output of `base::print(...)` and sends it to vsc together with information about the sourcefile and line
#' @export
#' @param ... Arguments passed to `base::cat()`
#' @param skipCalls The number of calls to skip when reporting the calling file and line. Can be used e.g. inside log functions.
#' @param showSource Whether to show the calling source file and line.
#' @return `invisible(x)`
.vsc.print <- function(x, ..., skipCalls=0, showSource=TRUE) {
  # TODO: consider correct environment for base::print(...)?
  # env <- sys.frame(-1)
  # ret <- capture.output(base::print(...), envir=env)

  if (session$state$isEvaluatingSilent()) {
    return(base::print(x, ...))
  }
  split <- session$splitOverwrittenOutput
  ret <- capture.output(base::print(x, ...), split=split)
  ret <- c(ret, "")
  printToVsc(ret, skipCalls+1, showSource = showSource)
  invisible(x)
}


#' Modified version of `base::message(...)` for vsc
#' 
#' Same as `base::message()` but uses `.vsc.cat` instead of `base::cat`
#' @param ... Same as `base::message`
#' @param domain Same as `base::message`
#' @param appendLF Same as `base::message`
#' @param showSource Whether to show the calling source file and line.
#' @param skipCalls The number of calls to skip when reporting the calling file and line. Can be used e.g. inside log functions.
#' @export
.vsc.message <- function(..., domain = NULL, appendLF = TRUE, showSource=TRUE, skipCalls=0){
  args <- list(...)
  cond <- if (length(args) == 1L && inherits(args[[1L]], "condition")) {
    if (nargs() > 1L) {
      warning("additional arguments ignored in message()")
    }
    args[[1L]]
  } else {
    msg <- .makeMessage(..., domain = domain, appendLF = appendLF)
    call <- sys.call()
    simpleMessage(msg, call)
  }
  defaultHandler <- function(c) {
    .vsc.cat(conditionMessage(c), file = stderr(), sep = "", skipCalls=skipCalls+5, showSource = showSource) # changed
  }
  withRestarts(
    {
      signalCondition(cond)
      defaultHandler(cond)
    },
    muffleMessage = function() NULL
  )
  invisible()
}


#' Modified version of `utils::str(...)` for vsc
#' 
#' Same as `utils::str` but uses VS Codes structured variable output.
#' 
#' @param object Same as `utils::str`
#' @param ... Same as `utils::str`
#' @param showSource Whether to show the calling source file and line.
#' @param skipCalls The number of calls to skip when reporting the calling file and line. Can be used e.g. inside log functions.
#' @export
.vsc.str <- function(object, ..., skipCalls=0, showSource=TRUE){
  args <- list(
    name = 'vscStrResult',
    rValue = list(object)
  )
  node <- session$rootNode$getEvalRootNode()$addChild(args)
  variable <- node$getContent()

  if(showSource){
    source <- getSource(sys.call(-skipCalls))
    line <- lget(source, 'line', 0)
  } else{
    source <- NULL
    line <- NULL
  }

  sendOutputEvent(
    output = "",
    category = "stdout",
    variablesReference = variable$variablesReference,
    source = source,
    line = line
  )

  if(session$splitOverwrittenOutput){
    utils::str(object, ...)
  }

  invisible(NULL)
}

#' Internal function to print to vsc
#' 
#' Sends text to vsc, together with source information
#' 
#' @param ret The text to be sent
#' @param skipCalls The number of calls to skip when reporting the calling file and line. Can be used e.g. inside log functions.
#' @param category The output category ("stdout", "stderr", ...)
#' @param showSource Whether to show the calling source file and line.
printToVsc <- function(ret, skipCalls=0, category="stdout", showSource=TRUE){
  output <- paste0(ret, collapse = "\n")

  if(showSource){
    source <- getSource(sys.call(-skipCalls))
    line <- lget(source, 'line', 0)
  } else{
    source <- NULL
    line <- NULL
  }

  sendOutputEvent(category, output = output, line=line, source=source)
}


#' @export
.vsc.print.help_files_with_topic <- function(h, ...) {
  viewer <- getOption("vsc.helpPanel", "Two")
  if (!identical(FALSE, viewer) && length(h) >= 1 && is.character(h)) {
    file <- h[1]
    path <- dirname(file)
    dirpath <- dirname(path)
    pkgname <- basename(dirpath)
    requestPath <- paste0(
      "/library/",
      pkgname,
      "/html/",
      basename(file),
      ".html"
    )
    success <- sendCustomEvent('viewHelp', list(requestPath = requestPath, viewer = viewer))
  } else{
    utils:::print.help_files_with_topic(h, ...)
  }
  invisible(h)
}


#' @export
.vsc.print.hsearch <- function(x, ...){
  viewer <- getOption("vsc.helpPanel", "Two")
  if (!identical(FALSE, viewer) && length(x) >= 1) {
    requestPath <- paste0(
      "/doc/html/Search?pattern=",
      tools:::escapeAmpersand(x$pattern),
      paste0("&fields.", x$fields, "=1",
        collapse = ""
      ),
      if (!is.null(x$agrep)) paste0("&agrep=", x$agrep),
      if (!x$ignore.case) "&ignore.case=0",
      if (!identical(
        x$types,
        getOption("help.search.types")
      )) {
        paste0("&types.", x$types, "=1",
          collapse = ""
        )
      },
      if (!is.null(x$package)) {
        paste0(
          "&package=",
          paste(x$package, collapse = ";")
        )
      },
      if (!identical(x$lib.loc, .libPaths())) {
        paste0(
          "&lib.loc=",
          paste(x$lib.loc, collapse = ";")
        )
      }
    )
    success <- sendCustomEvent('viewHelp', list(requestPath = requestPath, viewer = viewer))
  } else{
    utils:::print.hsearch(x, ...)
  }
  invisible(x)
}

#' Refresh Breakpoints
#' 
#' Refresh breakpoints known to the debugger
#' Can be used if breakpoints were invalidated by e.g. `load_all()` or `source()`
#' @export
.vsc.refreshBreakpoints <- function(envs=NULL){
  setStoredBreakpoints(envs)
}


#' Modified version of `pkgload::load_all()`
#' @export
.vsc.load_all <- function(...){
  internalLoadAll(..., refreshBreakpoints = TRUE)
}

internalLoadAll <- function(..., refreshBreakpoints=FALSE, loadSilently=FALSE){
  if(!requireNamespace('pkgload', quietly = TRUE)){
    stop('Package pkgload must be installed to use load_all!')
  }

  # normal load_all
  if(loadSilently){
    suppressMessages(ret <- pkgload::load_all(...))
  } else{
    ret <- pkgload::load_all(...)
  }
  ns <- ret$env

  # attach overwritten print/cat etc.
  attachList <- makeAttachList(list(
    overwritePrint = session$overwritePrint,
    overwriteCat = session$overwriteCat,
    overwriteMessage = session$overwriteMessage
  ))
  if(length(attachList)>0){
    attachEnv <- as.environment(attachList)
    parent.env(attachEnv) <- parent.env(ns)
    parent.env(ns) <- attachEnv
  }

  # store pkgname
  s <- format(ns)
  pkgName <- sub('^<environment: (?:package|namespace):(.*)>$', '\\1', s)
  session$debuggedPackages <- unique(c(session$debuggedPackages, pkgName))

  # refresh breakpoints (used if called curing session, not launch)
  if(refreshBreakpoints){
    exports <- as.environment(paste0('package:', pkgName))
    .vsc.refreshBreakpoints(list(ns, exports))
  }

  # return output from normal load_all
  invisible(ret)
}


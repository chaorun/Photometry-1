##### $Utility.R, Support for VS Photometry
##### Eric Dose, Bois d'Arc Observatory, Kansas, USA -- begun September 18 2015.

##### SUPPORT FILES ONLY in this file. ##########################################

make_safe_path <- function (folder, filename, extension="") {
# Pastes correctly regardless of duplicated "/". Disregard extension if it's in filename.
  gsub("/+","/",paste(trimws(folder),"/",trimws(filename),trimws(extension),sep=""),fixed=FALSE)
}

doFOVs <- function(func=NULL) {
  # Call external function 'func' on all current FOVs (objects).
  FOV_input_folder = "C:/Dev/Photometry/FOV"
  require(dplyr)
  require(stringi)
  all_files <- list.files(FOV_input_folder, full.names=FALSE, recursive=FALSE, include.dirs=FALSE) %>% 
    setdiff(list.dirs("C:/Dev/Photometry/FOV", full.names=FALSE))
  df <- data.frame(FOV_files=all_files, stringsAsFactors = FALSE) %>% 
    filter(!stri_startswith_fixed(FOV_files,"$"))
  target_types <- NULL
  for (i in 1:nrow(df)) {
    # cat(i, ": ", df$FOV_files[i], "\n")
    fov <- read_FOV_file(df$FOV_files[i] %>% strsplit(".txt") %>% unlist())
    # target_types <- target_types %>% c(fov$FOV_data$Target_type)
    func(fov)
  }
  # cat(unique(target_types))
}


read_FOV_file <- function (FOV_name, FOV_folder="C:/Dev/Photometry/FOV", format_version="1.3") {
  # Updated Sept 5 2016 for FOV schema version 1.3 (for both R and Python:photrix)
  require(stringi, quietly=TRUE)
  require(dplyr, quietly=TRUE)
  FOV_path   <- make_safe_path(FOV_folder,trimws(FOV_name),".txt")
  if (!file.exists(FOV_path)) {
    return (NA)
  }
  lines <- readLines(FOV_path, warn=FALSE)   # read last line even without EOL character(s).
  lines <- lines[nchar(trimws(lines))>=1]    # remove blank lines
  for (iLine in 1:length(lines)) {
    lines[iLine] <- lines[iLine] %>% 
      strsplit(";",fixed=TRUE) %>% unlist() %>% first() %>% trimws()  # remove comments
  }
  
  # Collect all DIRECTIVE LINES.
  directiveLines <- lines[stri_detect_regex(lines,'^#')] # detect and collect directive text lines.
  # Nested functions:
  directive_value <- function(key) {
    line  <- directiveLines[substring(directiveLines,1,nchar(key))==key][1]
    directive <- line %>% strsplit("[ \t]",fixed=FALSE) %>% unlist() %>% first()
    value <- line %>% substring(nchar(directive)+1) %>% trimws()  # all but the directive
    value
  }
  directive_words <- function(key) {
    value <- directive_value(key)
    if (is.na(value)) {
      words <- NA
    } else {
      words <- value %>% strsplit("[ \t]+",fixed=FALSE) %>% unlist() %>% trimws()
    }
    words
  }
  
  FOV_data <- list()

  #---------- Header section.
  FOV_data$FOV_name <- directive_value("#FOV_NAME")
  FOV_data$Format_version <- directive_value("#FORMAT_VERSION")
  if (FOV_data$Format_version != format_version) {  # verify before continuing
    cat(">>>>> ", FOV_name,": Format version required to be ", format_version, 
        " but read to be", FOV_data$Format_version, "\n")
    return (NA)
  }
  center_words <- directive_words("#CENTER")
  FOV_data$RA_center  <- get_RA_deg(center_words[1])
  FOV_data$Dec_center <- get_Dec_deg(center_words[2])
  FOV_data$Chart <- directive_value("#CHART")
  FOV_data$Date <- directive_value("#DATE")
  
  #---------- Main-Target section
  FOV_data$Main_target <- directive_value("#MAIN_TARGET")
  FOV_data$Target_type  <- directive_value("#TARGET_TYPE")
  FOV_data$Period <- directive_value("#PERIOD") %>% as.double()
  # as of 1.3, require both values for: JD, Mag_V, Color_VI.
  JD_words <- directive_words("#JD")
  FOV_data$JD_bright <- JD_words[1] %>% as.double()
  FOV_data$JD_faint  <- JD_words[2] %>% as.double()
  mag_v_words <- directive_words("#MAG_V")
  FOV_data$Mag_V_bright <- mag_v_words[1] %>% as.double()
  FOV_data$Mag_V_faint  <- mag_v_words[2] %>% as.double()
  color_vi_words <- directive_words("#COLOR_VI")
  FOV_data$Color_VI_bright <- color_vi_words[1] %>% as.double()
  FOV_data$Color_VI_faint <- color_vi_words[2] %>% as.double()

  #---------- Observing section.
  obs_style_words <- directive_words("#OBSERVING_STYLE")
  obs_style <- obs_style_words[1]
  valid_obs_styles <- c("Stare", "Monitor", "LPV", "Standard")
  if (!obs_style %in% valid_obs_styles) {
    cat(">>>>> ", FOV_name,": Invalid #OBSERVING_STYLE ", obs_style, "\n")
  }
  FOV_data$Observing_style <- obs_style
  
  FOV_data$Alert <- NA_real_  # default
  obs_values <- obs_style_words[-1]
  df_observing <- data.frame(stringsAsFactors = FALSE)
  for (obs_value in obs_values) {
    items <- strsplit(obs_value,"=",fixed=TRUE) %>% unlist() %>% strsplit("(",fixed=TRUE) %>% unlist()
    tag <- items[1]
    if (tag=="ALERT" & length(items)==2) {
      FOV_data$Alert <- items[2] %>% as.double()
      next
    }
    this_filter <- tag
    if (length(items)==1) {
      this_mag <- NA_real_
      this_count <- 1
    }
    if (length(items)==2) {
      loc_rt_paren <- stri_locate_first_fixed(items[2],")")[1,"end"]
      if (is.na(loc_rt_paren)) {
        this_mag <- items[2] %>% as.double()  # no right paren, therefore a mag
        this_count <- 1
      } else {
        this_mag <- NA_real_  # right paren at end, therefore a count
        this_count <- items[2] %>% substring(1,nchar(items[2])-1) %>% as.integer()
      }
    }
    if (length(items)==3) {
      this_mag <- items[2] %>% as.double()
      this_count <- items[3] %>% substring(1,nchar(items[3])-1) %>% as.integer()
    }
    df_observing <- df_observing %>% rbind(data.frame(Filter=this_filter, Mag=this_mag, Count=this_count))
  }
  FOV_data$Observing_table <- df_observing
  
  stare_hours_words <- directive_words("#STARE_HOURS")
  FOV_data$Stare_reference <- NA   # defaults for absence of this directive.
  FOV_data$Stare_start     <- 0.0  #  "
  FOV_data$Stare_stop      <- 0.0  #  "
  if (!is.na(stare_hours_words[1])){
    if (length(stare_hours_words) >= 2) {
      if (stare_hours_words[1]=="ANY" & length(stare_hours_words) >= 2) {
        FOV_data$Stare_reference <- stare_hours_words[1]
        FOV_data$Stare_start     <- 0.0
        FOV_data$Stare_stop      <- stare_hours_words[2] %>% as.double()
      }
      if (stare_hours_words[1] %in% c("MIN","MAX") & length(stare_hours_words) >= 3) {
        FOV_data$Stare_reference <- stare_hours_words[1]
        FOV_data$Stare_start     <- stare_hours_words[2] %>% as.double()
        FOV_data$Stare_stop      <- stare_hours_words[3] %>% as.double()
      }
    }
  }

  FOV_data$Max_exposure <- directive_value("#MAX_EXPOSURE") %>% as.double()
  FOV_data$Priority <- directive_value("#PRIORITY") %>% as.double()
  gap_score_words <- directive_words("#GAP_SCORE_DAYS")
  if (length(gap_score_words) >= 3) {
    FOV_data$Gap_score_days <- gap_score_words[1:3] %>% as.double()  # normal case.
  } else {
    FOV_data$Gap_score_days <- FOV_data$Period * c(0.01, 0.02, 0.05)
  }
  
  ACP_directive_lines <- directive_value("#ACP_DIRECTIVES") %>% strsplit("|",fixed=TRUE) %>% 
    unlist() %>% trimws()
  if (length(ACP_directive_lines) >= 3) {
    FOV_data$ACP_directives <- ACP_directive_lines
  } else {
    FOV_data$ACP_directives <- NA
  }
  FOV_data$ACP_comments <- directive_value("#ACP_COMMENTS")
  
  #---------- AAVSO Sequence section.
  # Parse #PUNCH lines (for later removing pixels from sky annulus in make_df_master()).
  df_punch <- data.frame(StarID=NA_character_, DNorth=NA_real_, DEast=NA_real_,
                         stringsAsFactors = FALSE)[FALSE,]  # empty data frame with defined columns.
  for (line in directiveLines) {
    directive <- line %>% strsplit("[ \t]",fixed=FALSE) %>% unlist() %>% first()
    if (directive=="#PUNCH") {
      value <- line %>% substring(nchar(directive)+1) # everything but the directive
      starID <- value %>% strsplit(":",fixed=TRUE) %>% unlist() %>% first() %>% trimws()
      terms <- value %>% strsplit(":",fixed=TRUE)  %>% unlist() %>% nth(2) %>% trimws() %>% 
        strsplit("[ \t]+",fixed=FALSE) %>% unlist() %>% trimws()
      dNorth <- as.numeric(terms[1])
      dEast  <- as.numeric(terms[2])
      df_thisLine <- data.frame(StarID=starID,  # should match one star name from the Star lines below.
                                DNorth=dNorth,      # in degrees; 0=360=North, 90=East
                                DEast=dEast,        # in arcseconds from center of named star
                                stringsAsFactors = FALSE)
      df_punch <- rbind(df_punch, df_thisLine)
    }
  }
  
  # Parse STAR lines (embedded lines from VPhot sequence):
  starsDirectiveAt <- charmatch("#STARS", lines)
  # Read table below #STARS line; StarID must be character string (never integers, even if they seem to be).
  df_star <- read.table(FOV_path,header=FALSE, sep="\t", skip=starsDirectiveAt, fill=TRUE, strip.white=TRUE,
                        comment.char=";", stringsAsFactors = FALSE,
                        col.names=c("StarID", "degRA", "degDec", "Mags", "StarType",6:10),
                        colClasses=c("character", "numeric", "numeric", "character", "character"))
  df_star <- df_star[!stri_startswith_fixed(df_star[,1],";"),1:5] # remove comments, keep only 1st 5 cols
  if (nrow(df_star)<=0) {
    df_star <- NA  # no star data, prob if VPhot sequence has not yet been developed, e.g.,first-time FOV).
  } else {         # normal case where star data was read properly.
    df_star$MagU <- NA
    df_star$MagB <- NA
    df_star$MagV <- NA
    df_star$MagR <- NA
    df_star$MagI <- NA
    
    # temporary lookup/cross-reference data frame
    mag_xref <- data.frame(passband=c("MagU","MagB","MagV","MagR","MagI"), stringsAsFactors = FALSE)
    rownames(mag_xref) <- c("1024","1","2","4","8") 
    
    # Make CH_rows (a row for each check and comp star) & Target (unknown) rows.
    CH_rows <- df_star[df_star$StarType %in% c("C","H"),]
    for (irow in 1:nrow(CH_rows)) {
      mag_entries <- trimws(unlist(strsplit(CH_rows$Mags[irow],  "|", fixed=TRUE)))
      for (mag in mag_entries) {
        mag_key_value <- trimws(unlist(strsplit(mag,"_",fixed=TRUE)))
        column_name   <- mag_xref[mag_key_value[1],]
        if (!is.na(column_name)) {
          mag_value <- as.numeric(mag_key_value[2])
          CH_rows[irow,column_name] <- ifelse(mag_value==0, NA, mag_value) # VPhot writes zero to mean NA.
        }
      }
    }
    
    # Add target (unknown) rows to make new df_star data frame.
    df_star <- rbind(CH_rows, df_star[df_star$StarType=="T",])  # Add rows for Target (unknown) stars.
    df_star$StarType[df_star$StarType=="C"] <- "Comp"           # Rename types...inelegant of course
    df_star$StarType[df_star$StarType=="H"] <- "Check"          #  "
    df_star$StarType[df_star$StarType=="T"] <- "Target"         #  "
    df_star <- df_star[order(df_star$StarType),]                # Sort rows by star type.
    df_star$Mags <- NULL                                        # Remove no-longer-needed Mags column.
    
    # Diagnostic checks & messages before returning results.
    if (substr(FOV_name,1,4)!="Std_") {
      if (sum(df_star$StarType=="Check")<=0) {
        cat(">>>>> WARNING: FOV file ",FOV_name," does not appear to be a Std field & has NO CHECK STAR.\n")
      }
    }
  }
  return(list(FOV_data=FOV_data, punch=df_punch, star_data=df_star))
}


get_RA_deg <- function (RA_string) {
  # argument must be either (1) one string of format "12:34:56.232323" (full hex string), or
  #    (2) already a numeric string between 0 and 360 (degrees string).
  str <- unlist(strsplit(RA_string,":",fixed=TRUE))
  if (length(str)==1) {
    RA_deg = as.double(RA_string)
  } else {
    str <- c(str,rep("0",3))
    RA_deg <- 15 * sum(as.numeric(str[1:3]) * c(1, 1/60, 1/3600))
  }
  if (RA_deg < 0 | RA_deg > 360 ) RA_deg = NA
  return(RA_deg)
}

get_Dec_deg <- function (Dec_string) {
  # argument must be either (1) one string of format "+12:34:56.232323" or "-12:34:56.232323" or "0:0:0"
  #   (full hex string), or (2) already a numeric string between -90 and +90 (degrees string).
  str <- unlist(strsplit(Dec_string,":",fixed=TRUE))
  if (length(str)==1) {
    Dec_deg = as.double(Dec_string)
  } else {
    str <- c(str,rep("0",3))
    Dec_sign <- sign(as.numeric(paste(str[1],"1",sep=""))) # append digit to prevent "-0" problem.
    Dec_deg <- Dec_sign * sum(abs(as.numeric(str[1:3])) * c(1, 1/60, 1/3600))
  }
  if (Dec_deg < -90 | Dec_deg > +90 ) Dec_deg = NA
  return(Dec_deg)
}

get_RA_hours <- function (RA_deg) {
  require(stringi, quietly=TRUE)
  deg <- RA_deg %% 360
  hours <- floor(deg/15.0)
  minutes <- floor(4 * (deg-15*hours))
  seconds <- (deg-15*hours-minutes/4) * 240
  return (paste0(stri_pad_left(hours,width=2,pad="0"), ":",
                 stri_pad_left(minutes,width=2,pad="0"), ":",
                 stri_pad_left(format(seconds,nsmall=1),width=4,pad="0")))
}

get_Dec_hex <- function(Dec_deg) {
  require(stringi, quietly=TRUE)
  Dec_deg <- as.double(Dec_deg)
  sign_str <- ifelse(Dec_deg < 0, "-", "+")
  abs_degrees = abs(Dec_deg)
  degrees <- floor(abs_degrees)
  minutes <- floor((60*abs_degrees) - (60*degrees))
  seconds <- round(3600*abs_degrees - (3600*degrees + 60*minutes))
  return (paste0(sign_str,
                 stri_pad_left(degrees, width=2, pad="0"), ":",
                 stri_pad_left(minutes, width=2, pad="0"), ":",
                 stri_pad_left(seconds, width=2, pad="0")))
}
      
distanceRADec <- function (RA1_deg, Dec1_deg, RA2_deg, Dec2_deg) {
  # Returns distance on sphere, in degrees, between 2 points in RA,Dec.
  # First, try short-distance "haversine formula".
  RA1  <- (pi/180) * RA1_deg # convert to radians as required by R fns.
  RA2  <- (pi/180) * RA2_deg
  Dec1 <- (pi/180) * Dec1_deg
  Dec2 <- (pi/180) * Dec2_deg
  distance <- 2 * asin(sqrt(sin((Dec2-Dec1)/2)^2 + cos(Dec1)*cos(Dec2)*(sin((RA2-RA1)/2)^2)))
  # If distance is not very small, use the "spherical law of cosines" formula instead.
  maxHaversineDistance <- 1 * (pi/180) # 1 degree, in radians
  if (distance > maxHaversineDistance) {
     distance <- acos(sin(Dec1)*sin(Dec2) + cos(Dec1)*cos(Dec2)*cos(RA2-RA1))
  }
  return (distance * (180/pi)) # return in degrees.
}

read_AAVSO_Chart <- function(chartID) {
  ##### Tests OK 20151220.
  require(rvest, quietly=TRUE)
  require(dplyr, quietly=TRUE)
  url <- paste("https://www.aavso.org/apps/vsp/photometry/?chartid=", chartID, 
               "&Ic=on&B=on&Rc=on&maglimit=16", sep="")
  df_url <- url %>% read_html() %>% html_table() %>% nth(1)
  if (ncol(df_url)!=10) {
    stop("Table is corrupt, does not have 10 columns.")
  }
  # Convert text in table to more useful quantities.
  df <- df_url %>% 
    mutate(ChartID=chartID) %>%
    mutate(RA_deg=NA, Dec_deg=NA, Bmag=NA, Berr=NA, Vmag=NA, Verr=NA, Rmag=NA, Rerr=NA, Imag=NA, Ierr=NA)
  for (iRow in 1:nrow(df)) {
    # Unfortunately, strsplit() & unlist() don't work with %>%, thus must use loop.
    df$RA_deg[iRow]  <- strsplit(df$RA[iRow],"[",fixed=TRUE) %>% unlist() %>% first() %>% get_RA_deg()
    df$Dec_deg[iRow] <- strsplit(df$Dec[iRow],"[",fixed=TRUE) %>% unlist() %>% first() %>% get_Dec_deg()
    splits <- strsplit(df$B[iRow],"[()]") %>% unlist()
    df$Bmag[iRow] <- splits[1] %>% getNumericOrNA()
    df$Berr[iRow] <- splits[2] %>% getNumericOrNA()
    splits <- strsplit(df$V[iRow],"[()]") %>% unlist()
    df$Vmag[iRow] <- splits[1] %>% getNumericOrNA()
    df$Verr[iRow] <- splits[2] %>% getNumericOrNA()
    splits <- strsplit(df$Rc[iRow],"[()]") %>% unlist()
    df$Rmag[iRow] <- splits[1] %>% getNumericOrNA()
    df$Rerr[iRow] <- splits[2] %>% getNumericOrNA()
    splits <- strsplit(df$Ic[iRow],"[()]") %>% unlist()
    df$Imag[iRow] <- splits[1] %>% getNumericOrNA()
    df$Ierr[iRow] <- splits[2] %>% getNumericOrNA()
  }
  return(df %>% select(-RA, -Dec, -B, -V, -Rc, -Ic, -matches("B-V")))
}

getNumericOrNA <- function(string) {
  suppressWarnings(as.numeric(string)) # if not numeric, just return NA silently.
}

getFITSheaderValues <- function (FITS_path=NULL, keys=NULL) {
  require(dplyr, quietly=TRUE)
  get_header_value <- function(header, key) {  # nested function.
    value <- header[which(header==key)+1]
    if (length(value)==0) value <- NA
    trimws(value)
  }
  fileHandle <- file(description=FITS_path, open="rb")
  header <- parseHdr(readFITSheader(fileHandle))
  close(fileHandle)
  
  header_list <- list()
  for (key in keys) {
    header_list[[key]] <- get_header_value(header, key)
  }
  return(header_list)
}

get_VSP_json_list <- function (chartID=NULL, chart_folder="C:/Dev/Photometry/FOV/Chart", 
                               make_file_if_absent=TRUE) {
  if (is.null(chartID)) {stop(">>>>> You must provide an existing AAVSO chartID to get_VSP_json_list",
                                    "e.g., chartID='X15603BRV'.")}
  # get from chart_input_folder; if not available, import from AAVSO website and write JSON for later use.
  fullpath <- make_safe_path(chart_folder, paste0(chartID,".txt"))
  if (file.exists(fullpath)) {
    json_text <- readLines(con=fullpath)
  } else {
    URL <- paste0("https://www.aavso.org/apps/vsp/api/chart/", trimws(chartID), "/?format=json")
    json_text <- readLines(con=URL, warn=FALSE)
    if (make_file_if_absent == TRUE) { writeLines(json_text, con=fullpath) }
  }
  require(jsonlite, quietly=TRUE)
  json_list <- fromJSON(json_text)
  return (json_list)
}

#####  LOCAL UTILITIES mostly for plots  #######################################################

load_df_master <- function(AN_top_folder="J:/Astro/Images/C14", AN_rel_folder=NULL) {
  if (is.null(AN_rel_folder)) {stop(">>>>> You must provide a AN_rel_folder, ",
                                    "e.g., AN_rel_folder='20151216'.")}
  source("C:/Dev/Photometry/$Utility.R")
  AN_folder   <- make_safe_path(AN_top_folder, AN_rel_folder)
  photometry_folder <- make_safe_path(AN_folder, "Photometry")
  path_df_master <- make_safe_path(photometry_folder, "df_master.Rdata")
  load(path_df_master)
  return(df_master)
}

load_modelList <- function(AN_top_folder="J:/Astro/Images/C14", AN_rel_folder=NULL) {
  if (is.null(AN_rel_folder)) {stop(">>>>> You must provide a AN_rel_folder, ",
                                    "e.g., AN_rel_folder='20151216'.")}
  source("C:/Dev/Photometry/$Utility.R")
  AN_folder   <- make_safe_path(AN_top_folder, AN_rel_folder)
  photometry_folder <- make_safe_path(AN_folder, "Photometry")
  path_masterModelList <- make_safe_path(photometry_folder, "masterModelList.Rdata")
  load(path_masterModelList)
  return(masterModelList)
}


#####  THEMES  ###############################################################################

SAS2016.bw.theme <- function(){ # use later for publication of SAS 2016 paper.
  th <- theme_bw()
  th <- th + theme(plot.title=element_text(size=rel(1.6),face="bold",color="gray32"))
  th <- th + theme(axis.text=element_text(size=rel(1.4),color="gray55"))  # both axes.
  th <- th + theme(axis.title.x=element_text(angle=0,size=rel(1.4),face="italic",color="gray50"))
  th <- th + theme(axis.title.y=element_text(angle=0,size=rel(1.4),face="italic",color="gray50"))
  th <- th + theme(legend.position="none")
}
#' read_quality_report
#'
#' Processes fastq files to look at read counts, read lengths,
#' and at what read cycle the quality drops below the \code{q}
#' quality threshold.
#' @usage read_quality_report(path, q, n, k)
#' @param path File path(s) to fastq or fastq.gz file(s).
#' @param q Quality score cutoff for the read. Will look at the mean average score for 
#' \code{k} bases beyond where the potential read length cutoff would be recommended.
#' @param k number of bases beyond the current to consider for quality cutoff.
#' @param n The number of records to sample from the fastq file.
#' @param cores The number of CPU cores/threads to use.
#' @import data.table
#' @import doParallel
#' @import parallel
#' @export
#' @return data.table

read_quality_report <- function(path, q = 25, k = 2, n = 5e+05, cores = 1){
  if(cores != 1){require(doParallel)}
  if(cores == 0){cores <- detectCores()-1}
  if(cores == 1){
    read_report <- data.table(file = character(), sample = character(), count = numeric(), 
                              length = numeric(), quality_length = numeric())
    for(file in path[!is.na(path)]){
      srqa <- ShortRead::qa(file, n = n)
      df <- srqa[["perCycle"]]$quality
      read_counts <- sum(srqa[["readCounts"]]$read)
      averages <- as.vector(by(df, df$Cycle, function(cycle){
        cycle$Score[min(which(cumsum(cycle$Score) >= sum(cycle$Score)/2))]
      }, simplify = TRUE))
      # averages <- rowsum(df$Score * df$Count, df$Cycle)/
      # rowsum(df$Count, df$Cycle)
      q_length <- length(averages)
      for(cycle in seq_along(averages)){
        if(mean(averages[cycle:(cycle+(k))], na.rm = T) < q){
          q_length <- cycle
          break
        }
      }
      read_report <- rbind(read_report, list(file, strsplit(basename(file), "_")[[1]][1], read_counts, 
                                             length(averages), q_length))
    }
  } else {
    cl <- makeCluster(cores, type="FORK")  
    registerDoParallel(cl)
    on.exit(stopCluster(cl))
    read_report <- foreach(i = seq_along(path[!is.na(path)]), .combine = 'rbind') %dopar% {
      file = path[i]
      srqa <- ShortRead::qa(file, n = n)
      df <- srqa[["perCycle"]]$quality
      read_counts <- sum(srqa[["readCounts"]]$read)
      averages <- as.vector(by(df, df$Cycle, function(cycle){
        cycle$Score[min(which(cumsum(cycle$Score) >= sum(cycle$Score)/2))]
      }, simplify = TRUE))
      # averages <- rowsum(df$Score * df$Count, df$Cycle)/
      # rowsum(df$Count, df$Cycle)
      q_length <- length(averages)
      for(cycle in seq_along(averages)){
        if(mean(averages[cycle:(cycle+(k))], na.rm = T) < q){
          q_length <- cycle
          break
        }
      }
      return(data.table(file = file, sample = strsplit(basename(file), "_")[[1]][1], count = read_counts, length = length(averages), quality_length = q_length))
    }  
  }
  return(read_report)
}
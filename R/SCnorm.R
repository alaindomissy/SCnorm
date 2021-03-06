#' @title SCnorm

#' @usage SCnorm(Data = NULL, Conditions = NULL, OutputName = NULL, 
#'    SavePDF = TRUE, PropToUse = .25, Tau = .5, reportSF = FALSE, 
#'    FilterCellNum = 10, K = NULL, NCores = NULL, FilterExpression = 0,
#'    Thresh = .1, ditherCounts = FALSE, withinSample = NULL, 
#'    useSpikes = FALSE)

#' @param Data matrix of un-normalized expression counts. Rows are genes and
#'    columns are samples.
#' @param Conditions vector of condition labels, this should correspond to
#'    the columns of the un-normalized expression matrix.
#' @param OutputName specify the path and/or name of output files.
#' @param SavePDF whether to automatically write and save the output plot as
#'    a PDF (default is TRUE).
#' @param PropToUse proportion of genes closest to the slope mode used for
#'    the group fitting, default is set at .25. This number #' mainly affects
#'    speed.
#' @param Tau value of quantile for the quantile regression used to estimate
#'    gene-specific slopes (default is median, Tau = .5 ).
#' @param reportSF whether to provide a matrix of scaling counts in the
#'    output (default = FALSE).
#' @param FilterCellNum the number of non-zero expression estimate required
#'    to include the genes into the SCnorm fitting
#' (default = 10). The initial grouping fits a quantile regression to each
#'    gene, making this value too low gives unstable fits.
#' @param K the number of groups for normalizing. If left unspecified, an
#'    evaluation procedure will determine the optimal value of K
#'    (recommended). If you're sure about specifiyng K, then a vector equal to
#'    the number of conditions may be used.
#' @param NCores number of cores to use, default is detectCores() - 1.
#' @param FilterExpression exclude genes having median of non-zero expression
#'    below this threshold from count-depth plots.
#' @param Thresh threshold to use in evaluating the sufficiency of K, default
#'    is .1.
#' @param ditherCounts whether to dither/jitter the counts, may be used for
#'    data with many ties, default is FALSE.
#' @param withinSample a vector of gene-specific features to correct counts
#'    within a sample prior to SCnorm. If NULL(default) then no correction will
#'    be performed. Examples of gene-specific features are GC content or gene
#'    length.
#' @param useSpikes whether to use spike-ins to perform between condition
#'    scaling (default=FALSE). Assumes spike-in names start with "ERCC-".

#' @description Quantile regression is used to estimate the dependence of
#'    read counts on sequencing depth for every gene. Genes with similar
#'     dependence are then grouped, and a second quantile regression is used to
#'    estimate scale factors within each group. Within-group adjustment for
#'    sequencing depth is then performed using the estimated scale factors to
#'    provide normalized estimates of expression. If multiple conditions are
#'    provided, normalization is performed within condition and then
#' normalized estimates are scaled between conditions. If withinSample=TRUE
#'    then the method from Risso et al. 2011 will be implemented.


#' @return List containing matrix of normalized expression (and optionally a
#'    matrix of size factors if reportSF = TRUE ).
#' @export


#' @importFrom parallel detectCores mclapply
#' @import stats
#' @import graphics
#' @importFrom grDevices colorRampPalette
#' @importFrom parallel detectCores mclapply
#' @import grDevices
#' @author Rhonda Bacher
#' @examples 
#'  
#'  data(ExampleData)
#'    Conditions = rep(c(1,2), each= 90)
#'    #DataNorm <- SCnorm(ExampleData, Conditions, 
#'    #OutputName = "MyNormalizedData", SavePDF=TRUE, FilterCellNum = 10)
#'    #str(DataNorm)

SCnorm <- function(Data=NULL, Conditions=NULL, OutputName=NULL, 
    SavePDF = TRUE, PropToUse = .25, Tau = .5, reportSF = FALSE, 
    FilterCellNum = 10, K = NULL, NCores = NULL, FilterExpression = 0, 
    Thresh = .1, ditherCounts=FALSE, withinSample=NULL, useSpikes=FALSE) {
  
    if (any(colSums(Data) == 0)) {stop("Data contains at least one 
      column will all zeros. Please remove these columns before 
        calling SCnorm(). Quality control on data is highly recommended prior
      to running SCnorm!")}
  
    Data <- data.matrix(Data)
    if(anyNA(Data)) {stop("Data contains at least one value of NA. 
      Unsure how to proceed.")}
    ## checks
    if (.Platform$OS.type == "windows") {
        NCores = 1
    }
    
    if (is.null(rownames(Data))) {rownames(Data) <- as.vector(sapply("X_", 
       paste0, 1:dim(Data)[1]))}
    if (is.null(colnames(Data))) {stop("Must supply sample/cell names!")}
    if (is.null(Conditions)) {stop("Must supply conditions.")}
    if (is.null(OutputName)) {OutputName = "MyData"}
    if (dim(Data)[2] != length(Conditions)) {stop("Number of columns in 
      expression matrix must match length of conditions vector!")}
    if (!is.null(K)) {message(paste0("SCnorm will normalize assuming, ", 
      K, " is the optimal number of groups. It is not advised to set this."))}
    if (is.null(NCores)) {NCores <- max(1, detectCores() - 1)}
    if (ditherCounts == TRUE) {RNGkind("L'Ecuyer-CMRG");
      set.seed(1);message("Jittering values introduces some randomness, 
        for reproducibility set.seed(1) has been set.")}
      
    Levels <- unique(Conditions) # Number of conditions
  
   
    if(!is.null(withinSample)) {
        if(length(withinSample) == dim(Data)[1]) {
          message("Using loess method described in ''GC-Content Normalization 
          for RNA-Seq Data'', Risso et al. to perform within-sample 
          normalization. For other options see the original publication and 
          package EDASeq." )
      
          correctWithin <- function(y, correctFactor) {
          
          #don't use zeros or outliers
          useg <- which(y > 0 & y <= quantile(y, probs=0.995)) 
          X <- correctFactor[useg]
          Y <- log(y[useg])
    
          calcL <- loess(Y ~ X)
          counts.fit <- predict(calcL, newdata = correctFactor)
          names(counts.fit) <- names(y)
          counts.fit[is.na(counts.fit)] <- 0
  
          scaleC <- y / exp(counts.fit - median(Y)) #correct
          return(scaleC)
        } ##from EDAseq v2.8.0
      
        Data = apply(Data, 2, correctWithin, correctFactor = withinSample)
        } else{
          message("length of withinSample should match the number of 
            genes in Data!")
        }
    }

    DataList <- lapply(1:length(Levels), function(x) {
        Data[,which(Conditions == Levels[x])]}) # split conditions
    Genes <- rownames(Data) 
    
    SeqDepthList <- lapply(1:length(Levels), function(x) {
        colSums(Data[,which(Conditions == Levels[x])])})
  
    NumZerosList <- lapply(1:length(Levels), function(x) {
        apply(DataList[[x]], 1, function(c) sum(c != 0)) })
    
    GeneFilterList <- lapply(1:length(Levels), function(x) {
        names(which(NumZerosList[[x]] >= FilterCellNum))})
  
    GeneFilterOUT <- lapply(1:length(Levels), function(x) {
        names(which(NumZerosList[[x]] < FilterCellNum))})
      
    names(GeneFilterOUT) <- paste0("GenesFilteredOutGroup", unique(Conditions))
  
    message("Gene filter is applied within each condition.")
  
    NM <- lapply(1:length(Levels), function(x) {
        message(paste0(length(GeneFilterOUT[[x]]), 
           " genes were not included in the normalization due to having less 
           than ", FilterCellNum, " non-zero values."))})
  
    message("A list of these genes can be accessed in output, 
    see vignette for example.") 
    
    
    
    # Get median quantile regr. slopes.
    SlopesList <- lapply(1:length(Levels), function(x) {
        GetSlopes(DataList[[x]][GeneFilterList[[x]],], SeqDepthList[[x]], 
            Tau, FilterCellNum, NCores, ditherCounts)})
  
 
    #   if k is NOT provided
    if (is.null(K)) {
     if(SavePDF==TRUE) {
         pdf(paste0(OutputName, "_k_evaluation.pdf"), height=10, width=10)
         par(mfrow=c(2,2)) }
  
      NormList <- lapply(1:length(Levels), function(x) {
        Normalize(Data = DataList[[x]], 
                  SeqDepth = SeqDepthList[[x]], Slopes = SlopesList[[x]],
                  CondNum = Levels[x], OutputName= OutputName,
                  PropToUse = PropToUse,
                  Tau = Tau, NCores= NCores, Thresh = Thresh, 
                  ditherCounts=ditherCounts)
      }) 
    
      if (SavePDF==TRUE) {  dev.off() }    
    }
  
  
    # if specific k then do:
    # if length of k is less than number of conditions.
    if (!is.null(K) ) {
      if (length(K) == length(Levels)) {
        NormList <- lapply(1:length(Levels), function(x) {
          SCnorm_fit(Data = DataList[[x]], 
                     SeqDepth = SeqDepthList[[x]], Slopes = SlopesList[[x]],
                     K = K[x], PropToUse = PropToUse, NCores = NCores, 
                     ditherCounts=ditherCounts)
        })
      } else if (length(K) == 1) {
        K <- rep(K, length(Levels))
        NormList <- lapply(1:length(Levels), function(x) {
          SCnorm_fit(Data = DataList[[x]], 
                     SeqDepth = SeqDepthList[[x]], Slopes = SlopesList[[x]],
                     K = K[x], PropToUse = PropToUse, NCores = NCores, 
                     ditherCounts=ditherCounts)
        }) 
      } else (stop("Check that the specification of K is correct!"))
    }    
  
  
  
    FilterCellProportion = lapply(1:length(Levels), function(x) {
        FilterCellNum / dim(DataList[[x]])[2]})
  
    NORMDATA <- do.call(cbind, lapply(1:length(Levels), function(x) {
        NormList[[x]]$NormData}))
  
    ## plot the normalized data to screen
    message("Plotting count-depth relationship for normalized data...")
    
    checkCountDepth(Data = Data, NormalizedData = NORMDATA,
                    Conditions = Conditions, OutputName = OutputName, 
                    SavePDF = SavePDF, Tau=Tau,
                     FilterCellProportion = FilterCellProportion, 
                     FilterExpression = FilterExpression, NCores = NCores, 
                     ditherCounts=ditherCounts)
  
  
  
  
    if (length(Levels) > 1) {
    
      # Scaling
      # Genes = Reduce(intersect, GeneFilterList)
      message("Scaling data between conditions...")
      ScaledNormData <- scaleNormMultCont(NormList, Data, Genes, useSpikes)
      names(ScaledNormData) <- c("NormalizedData", "ScaleFactors")
      ScaledNormData <- c(ScaledNormData, GeneFilterOUT)
      if(reportSF == TRUE) {
        return(ScaledNormData) 
      } else {
        ScaledNormData$ScaleFactors <- NULL
        return(ScaledNormData) 
      }
    } else {
      NormDataFull <- NormList[[1]]$NormData
      ScaleFactorsFull <- NormList[[1]]$ScaleFactors
    
      if(reportSF == TRUE) {
        FinalNorm <- list(NormalizedData = NormDataFull, 
            ScaleFactors = ScaleFactorsFull, GeneFilterOUT)
        return(FinalNorm) 
      } else {
        FinalNorm <-list(NormalizedData = NormDataFull, GeneFilterOUT)
        return(FinalNorm) 
      }
    }
  
    try(dev.off(), silent=TRUE)
  
    message("Done!")
  
  
  
}



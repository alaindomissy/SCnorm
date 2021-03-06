#' @title Evaluation the count-depth relationship before (or after) normalizing
#' the data.

#' @usage checkCountDepth(Data, NormalizedData= NULL, Conditions = NULL, 
#'  OutputName, SavePDF = TRUE, Tau = .5, FilterCellProportion = .10,
#'  FilterExpression = 0, NumExpressionGroups = 10, NCores=NULL,
#'  ditherCounts = FALSE)

#' @param Data matrix of un-normalized expression counts. Rows are genes
#'  and columns are samples.
#' @param NormalizedData matrix of normalized expression counts. Rows are
#'  genesand columns are samples. Only input this if evaluating already
#'  normalized data.
#' @param Conditions vector of condition labels, this should correspond to 
#'  the columns of the un-normalized expression matrix. If not provided data
#'  is assumed to come from same condition/batch.
#' @param OutputName specify the path and/or name of output files.
#' @param Tau value of quantile for the quantile regression used to
#'  estimate gene-specific slopes (default is median, Tau = .5 ). 
#' @param SavePDF whether to automatically write and save the output plot
#'  as a PDF (default is TRUE).
#' @param FilterCellProportion the proportion of non-zero expression estimates
#'  required to include the genes into the evaluation. Default is .10. 
#' @param FilterExpression exclude genes having median of non-zero expression
#'  below this threshold from count-depth plots.
#' @param NumExpressionGroups the number of groups to split the data into,
#'  groups are split into equally sized groups based on non-zero median
#'  expression. 
#' @param NCores number of cores to use, default is detectCores() - 1.
#' @param ditherCounts whether to dither/jitter the counts, may be used for
#'  data with many ties, default is FALSE. 

#' @description Quantile regression is used to estimate the dependence of read
#'  counts on sequencing depth for every gene. If multiple conditions are
#'  provided, a separate plot is provided for each. Can be used to evaluate
#'  the extent of the count-depth relationship in the dataset or can be be
#'  used to evaluate data normalized by alternative methods.

#' @return outputs a plot.
#' @export

#' @author Rhonda Bacher
#' @importFrom parallel detectCores mclapply
#' @import stats
#' @import graphics
#' @importFrom grDevices colorRampPalette
#' @importFrom parallel detectCores mclapply
#' @examples 
#'  
#' data(ExampleData)
#' Conditions = rep(c(1,2), each= 90) 
#' #checkCountDepth(Data = ExampleData, Conditions = Conditions, 
#'   #OutputName = "check_exampleData", FilterCellProportion = .1)

checkCountDepth <- function(Data, NormalizedData= NULL, Conditions = NULL, 
    OutputName=NULL, SavePDF=TRUE, Tau = .5, FilterCellProportion = .10, 
    FilterExpression = 0, NumExpressionGroups = 10, NCores=NULL, 
    ditherCounts = FALSE) {
      
      
    Data <- data.matrix(Data)
    if(anyNA(Data)) {stop("Data contains at least one value of NA. 
      Unsure how to proceed.")}
    
    ## checks
    if (.Platform$OS.type == "windows") {
        NCores = 1
    }
    
    if(is.null(rownames(Data))) {rownames(Data) <- as.vector(sapply("X_", 
        paste0, 1:dim(Data)[1]))}
    if(is.null(colnames(Data))) {stop("Must supply sample/cell names!")}
    if(is.null(Conditions)) {Conditions <- rep("1", dim(Data)[2])}
    if (is.null(OutputName)) {OutputName = "count-depth-relationship.pdf"}
    if(dim(Data)[2] != length(Conditions)) {stop("Number of columns in 
         expression matrix must match length of conditions vector!")}
    if(is.null(NCores)) {NCores <- max(1, detectCores() - 1)}
         Levels <- levels(as.factor(Conditions)) # Number of conditions
    if (ditherCounts == TRUE) {RNGkind("L'Ecuyer-CMRG");set.seed(1);
         message("Jittering values introduces some randomness, for 
           reproducibility set.seed(1) has been set")}

    if(length(FilterCellProportion) > 1 & !is.list(FilterCellProportion)) {
         FilterCellProportion <- as.list(FilterCellProportion)}
    if(length(FilterCellProportion) == 1) { 
        FilterCellProportion <- rep(FilterCellProportion, length(Levels))
        FilterCellProportion <- as.list(FilterCellProportion)}
  
    # Can't use less then FilterCellNum = 10


    DataList <- lapply(1:length(Levels), function(x) {
        Data[,which(Conditions == Levels[x])]}) # split conditions

    FilterCellProportion <-  lapply(1:length(Levels), function(x) {
        max(FilterCellProportion[[x]], 10 / dim(DataList[[x]])[2])})

    SeqDepthList <- lapply(1:length(Levels), function(x) {
        colSums(Data[,which(Conditions == Levels[x])])})

    PropZerosList <- lapply(1:length(Levels), function(x) {
        apply(DataList[[x]], 1, function(c) { 
            sum(c != 0)}) / length(SeqDepthList[[x]])})

    MedExprAll <- apply(Data, 1, function(c) median(c[c != 0]))

    MedExprList <- lapply(1:length(Levels), function(x) {
        apply(DataList[[x]], 1, function(c) median(c[c != 0])) })

    BeforeNorm <- TRUE
    #switch to the normalized data:
    if(!is.null(NormalizedData)) {  
       DataList <- lapply(1:length(Levels), function(x) {
       NormalizedData[,which(Conditions == Levels[x])]})
       BeforeNorm <- FALSE
    }

    GeneFilterList <- lapply(1:length(Levels), function(x) {
        names(which(PropZerosList[[x]] >= FilterCellProportion[[x]] & 
          MedExprAll >= FilterExpression))})
    NM <- unlist(lapply(1:length(Levels), function(x) {
            length(GeneFilterList[[x]] )}))
    if(any(NM == 0)) {stop("No genes pass the filter specified! 
        Try lowering thresholds or perform more QC on your data.")}

    # Get median quantile regr. slopes.
    SlopesList <- lapply(1:length(Levels), function(x) {
          GetSlopes(DataList[[x]][GeneFilterList[[x]],], 
           SeqDepthList[[x]], Tau, FilterCellNum = 10, 
           NCores, ditherCounts)})


    if (SavePDF == TRUE) { 
        pdf(paste0(OutputName, "_count-depth_evaluation.pdf"), height=5, 
                width=5)}
  
    lapply(1:length(Levels), function(x) {
    initialEvalPlot(MedExpr = MedExprList[[x]][GeneFilterList[[x]]], 
        SeqDepth = SeqDepthList[[x]], Slopes = SlopesList[[x]], 
        Name = Levels[[x]], NumExpressionGroups, BeforeNorm = BeforeNorm)})

    if (SavePDF == TRUE){  dev.off() }

    }

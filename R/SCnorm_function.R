#' @title Fit group quantile regression for K groups
#' @usage SCnorm_fit(Data, SeqDepth, Slopes, K, PropToUse, 
#' Tau, NCores, ditherCounts)

#' @inheritParams SCnorm
#' @inheritParams Normalize

#' @description For each group K, a quantile regression is fit over all genes
#'    (PropToUse) for a grid of possible degree's d and quantile's tau. 
#' For each value of tau and d, the predicted expression values are obtained
#'    and regressed against the original sequencing depths.  The optimal tau
#'    and d combination is chosen as that closest to the mode of the gene
#'    slopes.
#' @return normalized expression matrix and matrix of scaling factors.
#' @author Rhonda Bacher
#' @importFrom cluster clara
#' @importFrom moments skewness

SCnorm_fit <- function(Data, SeqDepth, Slopes, K, PropToUse = .25, Tau = .5, 
      NCores = NCores, ditherCounts) {

    
    SeqDepth <- data.table(Depth = log(SeqDepth), Sample = names(SeqDepth))
      #use LOG

    Genes <- rownames(Data)
    DataFiltered <- Data[names(Slopes),]
    logData <- data.table(Gene = rownames(DataFiltered),
        redobox(DataFiltered[,-1], 0)) # use LOG
  
  
    sreg <- list()
    grouping <- clara(as.matrix(Slopes), K)
    for(i in 1:K) {
        sreg[[i]] <- Slopes[names(which(grouping$clustering == i))] }

    #merge small clusters together, groups with less than 100 genes.
    Centers <- as.vector(grouping$medoids)
    SIZES = unlist(lapply(sreg, function(x) length(x)))
    while(any(SIZES < 100)) {
        i = which.min(SIZES)
        tomatch <- sort(abs(Centers - Centers[i]))[2]
        ADDTO <- which(abs(Centers - Centers[i]) == tomatch)
        sreg[[ADDTO]]<-c(sreg[[ADDTO]], sreg[[i]])
        sreg[[i]] <- NULL
        Centers <- Centers[-i]

    SIZES <- unlist(lapply(sreg, function(x) length(x)))
    }


    K = length(sreg) # update k


    NormData <- c()
    ScaleFactors <- c()

    ##normalize within each group
    if (.Platform$OS.type == "windows") {
      NCores = 1
    }

    for(i in 1:K) {
      qgenes <- names(sreg[[i]])
    
      try(dskew <- skewness(sreg[[i]])) 

      ##only want to use modal genes for speed
      rqdens <- density(Slopes[qgenes], from = min(Slopes[qgenes], 
          na.rm=TRUE), to = max(Slopes[qgenes], na.rm=TRUE))
      peak <- which.max(rqdens$y)
  
      if (is.na(dskew) == FALSE & abs(dskew) > .5) {
          PEAK <- rqdens$x[peak]
          } else { PEAK <- mean(sreg[[i]])}
  
  # use 25% of data near mode, faster
      NumToSub <- ceiling(length(qgenes) * PropToUse) 
      ModalGenes <- names(sort(abs(PEAK - Slopes[qgenes]))[1:NumToSub])
      
      InData <- subset(logData, Gene %in% ModalGenes)
      Melted <- data.table::melt(InData, id="Gene")
      colnames(Melted) <- c("Gene", "Sample", "Counts")

      LongData <- merge(Melted, SeqDepth, by="Sample")
      O <- LongData$Depth
      Y <- LongData$Counts
      
      taus <- seq(.05, .95, by=.05)
      D <- 6
      Grid <- expand.grid(taus, seq(1:6))
                      
      AllIter <- unlist(mclapply(X = 1:nrow(Grid), FUN = GetTD, 
          InputData = list(O, Y, SeqDepth$Depth, Grid, Tau, ditherCounts),
           mc.cores = NCores))
      
      D <- Grid[which.min(abs(PEAK - AllIter)),2]; 
      
      TauGroup <- Grid[which.min(abs(PEAK - AllIter)),1];
      
      polyX <- poly(O, degree = D, raw = FALSE)
      Xmat <- data.table(model.matrix( ~ polyX ))
      polydata <- data.frame(Y = Y, Xmat = Xmat[,-1])

      rqfit <- rq(Y ~ ., data = polydata, na.action = na.exclude, 
              tau = TauGroup, method="fn")
  
      revX <- data.frame(predict(polyX, SeqDepth$Depth))
      colnames(revX) <- colnames(polydata[-1])
      
      pdvalsrq <- predict(rqfit, newdata=data.frame(revX))
      names(pdvalsrq) <- rownames(SeqDepth)

      SF_rq <- exp(pdvalsrq) / exp(quantile(Y, probs = TauGroup, 
                  na.rm = TRUE))
      
      normdata_rq <- t(t(DataFiltered[qgenes, ]) / as.vector(SF_rq))
      rownames(normdata_rq) <- qgenes

      NormData <- rbind(NormData, normdata_rq)
      
      SFmat <- matrix(rep(SF_rq, length(qgenes)), nrow = length(qgenes), 
                  byrow = TRUE)
      rownames(SFmat) <- qgenes
      colnames(SFmat) <- names(SF_rq)
      
      ScaleFactors <- rbind(ScaleFactors, SFmat)

    }



    toput1 <- setdiff(Genes, rownames(NormData));
    if(length(toput1) > 0) {
    
      NormData <- rbind(NormData, Data[toput1,]);
      rownames(NormData)[which(rownames(NormData)=="")] <- toput1
    
      SFones <- matrix(rep(rep(1,dim(Data)[2]), length(toput1)), 
                    nrow=length(toput1), byrow=TRUE)
        rownames(SFones) <- toput1
        colnames(SFones) <- colnames(ScaleFactors)
        ScaleFactors <- rbind(ScaleFactors, SFones); 
    }
    NormData <- NormData[Genes, ]
    ScaleFactors <- ScaleFactors[Genes, ]

    NORM = list(NormData = NormData, ScaleFactors = ScaleFactors)
    return(NORM)
}

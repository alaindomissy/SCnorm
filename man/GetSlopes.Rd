% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/GetSlopes.R
\name{GetSlopes}
\alias{GetSlopes}
\title{Estimate gene specific count-depth relationships}
\usage{
GetSlopes(Data, SeqDepth, Tau, FilterCellNum, NCores, ditherCounts)
}
\arguments{
\item{Data}{matrix of un-normalized expression counts. Rows are genes and
columns are samples.}

\item{SeqDepth}{vector of sequencing depths estimated as columns sums of
un-normalized expression matrix.}

\item{Tau}{value of quantile for the quantile regression used to estimate
gene-specific slopes (default is median, Tau = .5 ).}

\item{FilterCellNum}{the number of non-zero expression estimate required to
include the genes into the SCnorm fitting (default = 10). The initial}

\item{NCores}{number of cores to use, default is detectCores() - 1.}

\item{ditherCounts}{whether to dither/jitter the counts, may be used for data
with many ties, default is FALSE.}
}
\value{
vector of estimated slopes.
}
\description{
This is the gene-specific fitting function, where a median 
   (Tau = .5) quantile regression is fit for each gene. Only genes having at
   least 10 non-zero expression values are considered.
}
\examples{
 data(ExampleData)
 #myslopes <- GetSlopes(ExampleData)
}
\author{
Rhonda Bacher
}

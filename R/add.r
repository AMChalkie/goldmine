# -----------------------------------------------------------------------------
#' Make a data.table from a GRanges or a data.frame
#'
#' Given a data.frame or GRanges, a data.table object will be created. If the input is already a data.table, it is simply returned.
#' @param obj A data.frame or GRanges
#' @return A data.table made from the data in obj.
#' @export
makeDT <- function(obj)
{
	myclass <- class(obj)[1]
	if(myclass=="GRanges")
	{
		# Convert GRanges to DT
		obj.dt <- data.table(as(obj,"data.frame"))
		setnames(obj.dt,"seqnames","chr")
		return(obj.dt)
	} else if(myclass=="data.frame")
	{
		# Convert DF to DT
		return(data.table(obj))
	} else if(myclass=="data.table")
	{
		# Already a DT, just return it back
		return(data.table(obj))
	} else
	{
		# Some bad input, throw error
		stop("GRanges, data.frame, or data.table object required as input")
	}
}
# --------------------------------------------------------------------

# -----------------------------------------------------------------------------
#' Add columns to query with distance to nearest subject and subject id(s)
#'
#' @param query Genomic regions to find nearest genes for as a GRanges, data.frame, or data.table with the columns "chr", "start", and "end"
#' @param query Genomic regions to find nearest genes for as a GRanges, data.frame, or data.table with the columns "chr", "start", and "end"
#' @param id Column name of the id field in subject to report as the nearest id(s). In case of ties, a comma separated list will be returned.
#' @param prefix Append this string to names of the added columns
#' @export
addNearest <- function(query,subject,id="name",prefix="subject")
{
	#subject.dt <- as(as(subject,"data.frame"),"data.table")
	query.dt <- makeDT(query)
	subject.dt <- makeDT(subject)

	if(!(id %in% colnames(subject.dt))){stop(paste0("id field \"",id,"\" is not a column in subject"))}

	query.gr <- makeGRanges(query)
	subject.gr <- makeGRanges(subject)

	# Get distances
	dist <- as.data.frame(distanceToNearest(query.gr,subject.gr))$distance

	# Get names
	fo <- data.table(as.data.frame(nearest(query.gr,subject.gr,select="all")))
	fo$name <- subject.dt[fo$subjectHits,][[id]]
	fo <- fo[,list(name2=toString(unique(name))),by=queryHits]
	matched <- data.frame(id=1:length(query.gr),name=NA)
	matched[fo$queryHits,]$name <- fo$name2

	query.dt[,eval(paste(prefix,"nearest",sep=".")):=matched$name]
	query.dt[,eval(paste(prefix,"dist",sep=".")):=dist]
	return(query.dt)
}
# --------------------------------------------------------------------

# -----------------------------------------------------------------------------
#' Add columns with distance to nearest gene and gene symbol(s)
#'
#' @param query Genomic regions to find nearest genes for as a GRanges, data.frame, or data.table with the columns "chr", "start", and "end"
#' @param geneset Select one of "ucsc" for the UCSC Genes (from the knownGene table), "refseq" for RefSeq genes (from the refFlat table), or "ensembl" for the Ensembl genes (from the ensGene table)
#' @param genome UCSC genome name to use (e.g. hg19, mm10)
#' @param cachedir Path where cached UCSC tables are stores
#' @export
addGenes <- function(query,geneset,genome,cachedir)
{
	genes <- getGenes(geneset,genome,cachedir)
	addNearest(query,genes,id="name",prefix=geneset)
}
# --------------------------------------------------------------------

# -----------------------------------------------------------------------------
#' Load table of gene ranges via UCSC Genome Browser tables
#'
#' @param geneset Select one of "ucsc" for the UCSC Genes (from the knownGene table), "refseq" for RefSeq genes (from the refFlat table), or "ensembl" for the Ensembl genes (from the ensGene table)
#' @param genome UCSC genome name to use (e.g. hg19, mm10)
#' @param cachedir Path where cached UCSC tables are stores
#' @export
getGenes <- function(geneset="ucsc",genome,cachedir=NULL)
{
	# Validate geneset
	if(!(geneset %in% c("ucsc","refseq","ensembl"))){stop("geneset must be one of \"ucsc\", \"refseq\", or \"ensembl\"")}

	if(geneset=="ucsc")
	{
		kg <- getUCSCTable("knownGene",genome,cachedir)
		kgx <- suppressWarnings(getUCSCTable("kgXref",genome,cachedir))
		ki <- getUCSCTable("knownIsoforms",genome,cachedir)
		setnames(kg,"name","kgID")
		setnames(ki,"transcript","kgID")
		setkey(kg,kgID)
		setkey(kgx,kgID)
		setkey(ki,kgID)
		kg <- ki[kg,]
		genes <- kgx[kg,list(chr=chrom,start=txStart+1,end=txEnd,strand=strand,name=geneSymbol,gene.id=clusterId)]
		genes[,isoform.id:=kgID]
		genes[,kgID:=NULL]
		return(genes)
	} else if(geneset=="refseq")
	{
		rg <- getUCSCTable("refFlat",genome,cachedir)
		genes <- rg[,list(chr=chrom,start=txStart+1,end=txEnd,strand=strand,name=geneName,gene.id=geneName,isoform.id=name)]
		return(genes)
	} else if(geneset=="ensembl")
	{
		eg <- getUCSCTable("ensGene",genome,cachedir)
		en <- getUCSCTable("ensemblToGeneName",genome,cachedir)
		setkey(eg,"name")
		setkey(en,"name")
		genes <- en[eg,list(chr=chrom,start=txStart+1,end=txEnd,strand=strand,name=value,gene.id=name2)]
		genes[,isoform.id:=name]
		genes[,name:=NULL]
		return(genes)
	}
}
# --------------------------------------------------------------------

######################################################################################
# Either download or install the required library from CRAN or bioconductor
#######################################################################################

install.packages.if.necessary <- function(CRAN.packages=c(), bioconductor.packages=c()) {
  #if (length(bioconductor.packages) > 0) {
  #  source("http://bioconductor.org/biocLite.R")
  #}
  
  for (p in bioconductor.packages) {
    if (!require(p, character.only=T)) {
      BiocManager::install(p,version = "3.8") 
    }
    library(p,lib.loc="~/R/win-library/3.5",character.only=T)
  }
  
  for (p in CRAN.packages) {	
    if (!require(p, character.only=T)) { 	
      install.packages(p) 	
    }	
    #library(p, lib.loc="~/R/win-library/3.5",character.only=T) 
    library(p, lib.loc="~/R/win-library/3.5",character.only=T)
  }
}


###################################################################################################
### get gene name from uniprot ID , 
## Input: x, vector of uniprot id 
## Output: table with defined attributes in columns
getGeneName <- function(x){
  mart = useMart("ensembl",dataset="hsapiens_gene_ensembl")
  list <- getBM(attributes=c('uniprotswissprot', 'external_gene_name'),
                filters = 'uniprotswissprot', 
                values =x, 
                mart = mart)
  return(list)
}


####################################################################################################
### Build combination of all complex and proteins
buildComplexProtein <- function(corum_complex_inspected){
  complex_protein <- data.frame(matrix(NA, ncol=4, nrow=0))
  for (i in 1:dim(corum_complex_inspected)[1]){
    pr <- strsplit(corum_complex_inspected$subunits.UniProt.IDs.[i],"\\|")[[1]]
    gn <- strsplit(corum_complex_inspected$geneName[i],"\\|")[[1]]
    if(length(gn)>length(pr)){
      gn <- c()
      for(p in pr){
        gn <- c(gn,getGeneName(p)$external_gene_name[1])
      }
    }
    
    if(length(pr)!=0 & !is.na(pr)& pr!="NA"){
      complex_protein<- rbind(complex_protein ,
                              data.frame(cbind(rep(as.character(corum_complex_inspected[i,"ComplexName"]),length(pr)),
                                               as.character(pr),
                                               as.character(gn),
                                               rep(corum_complex_inspected$count[i],length(pr)),
                                               rep(corum_complex_inspected$subunits.UniProt.IDs.[i],length(pr)))
                              )
      )
    }else{}
  }
  colnames(complex_protein) <- c("ComplexName","uniprotID","GeneName","count","Identifers")
  return(complex_protein)
}

####################################################################################################
#' Enrich list of uniprot ID based complex protein distribution


enrichComplex <- function(significant_uniprot,complex_protein){
  ### list of annotated proteins
  k <- length(significant_uniprot)
  
  ### list of proteins in human complexes
  N <-length(unique(unlist(complex_protein$uniprotID)))
  
  selected_complex_count <- complex_protein %>%
    dplyr::filter(uniprotID %in% significant_uniprot) %>%
    dplyr::group_by(ComplexName) %>%
    dplyr::summarise(count=as.numeric(as.character(count[1])),
              selected_count= as.numeric(n()),
              GeneRatio=selected_count/count,
              complete_members=Identifers[1],
              Identifiers=paste(uniprotID, collapse="|")) %>%
    dplyr::mutate(pValue = phyper(q=as.numeric(selected_count),m=as.numeric(count), n =N-as.numeric(count), k=k , lower.tail=FALSE))
  
  
  selected_complex_count$p.adj <- p.adjust(selected_complex_count$pValue, "BH")
  selected_complex_count_test <- selected_complex_count %>% filter(p.adj<5e-02&as.numeric(count)>1) %>% arrange(p.adj,desc(selected_count))
  return(selected_complex_count_test)
}

########################################################################################################33
#' Enrich each group by complex database
#' Inputs:
#' 1. dataframe (uniprot ID, cluster ID)
#' 2. dataframe of enriched complexes and their properties
#' 3. complex protein membership

compareCluster_Complex <- function(dz,selected_complex_count_test,complex_protein){
  Sig_enriched <- data.frame(matrix(NA, ncol=9, nrow=0))
  colnames(Sig_enriched) <- c("ComplexName", "count", "selected_count", "GeneRatio", "complete_members", "Identifiers", "pValue", "p.adj", "cluster")
  
  for (i in unique(unlist(dz[["target"]]))){
    Sig <- unlist(unname(dz[["uniprotID"]][dz[["target"]]==i]))
    enr_df<- enrichComplex(Sig,complex_protein)
    enr_df$target <- rep(i,dim(enr_df)[1])
    Sig_enriched <- rbind(Sig_enriched,enr_df)
  }
  Sig_enriched <- Sig_enriched[as.character(Sig_enriched$ComplexName) %in% as.character(unlist(selected_complex_count_test[,"ComplexName"]$ComplexName)),]
  
  return(Sig_enriched)
  
}


######################################################################################################
## Plot enrichment status of related complex

plot_related_enriched <- function(res, related_complex_enriched,target){
  result <- data.frame(matrix(NA, nrow=0, ncol=3))
  for(i in unique(res$target)){
    print(i)
    res1 <- res %>% filter(target==i, ComplexName %in% related_complex_enriched$ComplexName)
    x <- cbind(
      as.character(related_complex_enriched$ComplexName),
      res1$GeneRatio[match(related_complex_enriched$ComplexName,res1$ComplexName)],
      rep(i, dim(related_complex_enriched)[1])
      )
    result <- rbind(result,data.frame(x))
  }
  colnames(result) <- c("ComplexName","GeneRatio","target")
  result$GeneRatio <- as.numeric(as.character(result$GeneRatio))
  result$ComplexName <- as.character(result$ComplexName)
  result$GeneRatio[is.na(result$GeneRatio)] <- 0
  png(paste0("F:/NCBP/recent/image/Related_complex_barplot_",target,".png"), width = 700, height = 450+(dim(result)[1]*dim(result)[2]-90)*2)
  qq <- ggplot(mapping = aes(x=ComplexName, y=GeneRatio, fill=target))+
    geom_bar(data = related_complex_enriched, fill="gray",stat="identity")+
    geom_bar(data = result, stat="identity",position="dodge")+
    coord_flip()
  print(qq)
  dev.off()
}


##############################################################################################
#' Plot enriched clusters by complex

plot_cluster <- function(test,related_complex_enriched,title="", r=0.4,target){
  test <- test[test$GeneRatio>r,] 
  png(paste0("F:/NCBP/recent/image/",gsub(" ","_",gsub("\\s*\\([^\\)]+\\)","",as.character(title))),"_",target,"_",r,".png"), width = 650+(length(unique(test$target))-1)*15, height = 470+(dim(test)[1]-30)*10)
  q <- ggplot(test) +
    geom_point(aes(x=target, y=ComplexName, col= average_intensity ,size=GeneRatio)) +
    theme(axis.text.x = element_text(angle = 90, hjust = 1),
          axis.title.x=element_blank(),
          axis.title.y=element_blank())+
    scale_color_gradient(low="blue",high='red',na.value="gray")
    #scale_size_area()
  print(q)
  dev.off()
}

#######################################################################################
plotly_cluster <- function(test = NCBP$related_complex_average_intensity,
                           related_complex_enriched = NCBP$related_complex_enriched,
                           title="Related complex enrichment (average intensity& gene ratio)",
                           r=0.3,
                           target="target"){
  test <- data.frame(test[test[["GeneRatio"]]>r ,])
  test2 <- test[as.character(test$ComplexName) %in% as.character(test %>% group_by(ComplexName) %>% summarize(min(GeneRatio)>0)%>% .$ComplexName) ,] 
  
  vals <- unique(scales::rescale(c(test$average_intensity)))
  o <- order(vals, decreasing = FALSE)
  cols <- scales::col_numeric(c("Green","Red"), domain = NULL)(vals)
  colz <- setNames(data.frame(vals[o], cols[o]), NULL)
  
  q <- plot_ly(test, x=~target, y=~ComplexName,
               legendgroup = ~20*GeneRatio,showlegend = T, colors = colorRamp(c("red", "green")),
               height = 360+(dim(test2 )[1]-20)*20,
               type="scatter",mode ="markers",
               marker = list(color= ~average_intensity ,size=~20*GeneRatio,
                             colorbar=list(
                               title="avg Intensity"
                             ),
                             colorscale=colz,
                             reversescale =F),
               text = ~paste(paste("average intensity: ", average_intensity),paste("protein ratio", GeneRatio), sep="\n"))%>%
    layout(
      title = paste0(gsub("\\s*\\([^\\)]+\\)","",as.character(title))," ",target," ",r),
      xaxis = list(title = "Target")
     # margin = list(l = 100)
    )
  return(q)
}

#######################################################################################
t_test <- function(subs) t.test(unlist(unname(subs[,cases])),unlist(unname(subs[,controls])))$p.value



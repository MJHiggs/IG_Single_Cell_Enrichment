#### STAGE 0 - NECESSARY SETUP (RUN EVERY TIME) ###############################################################

#read in packages#
library(data.table)
library(tidyverse)
library(cowplot)
library(ggnewscale)
library(liger)
BiocManager::install("GEOquery")
library(GEOquery)

#set working directory/ignore if running from current directory#
setwd(...)

#"Imprinted_Gene_List.csv" - read in premade Imprinted gene file- gene name, ensmbl, chromosome order and sex_bias#
IG <- read.csv(...)

#Read in the supplementary file from GSE76381#
getGEOSuppFiles("GSE129788")
untar("GSE129788/GSE129788_RAW.tar", exdir = "GSE129788/")

### STAGE 1 DATA PREPARATION AND UPREGULATION ANALYSIS ###################################################################################

#function to cut string from right side#
substrRight <- function(x, n){
  substr(x, nchar(x)-n+1, nchar(x))
}

#Set directory to raw files and read in files, merge them into one dataframe with all cells#
setwd("GSE129788/")
files <- list.files()[-1:-2]
data <- fread(files[1])
Final <- data.frame("gene" = data$V1)

#Loop over each dataframe, remove V1 and cbind to the total#
for(a in 1:8){
  data <- fread(files[a])
  data$V1 = NULL
  Final <- cbind(Final, data)
}

#Create scaling factors to normalize expression data by - 10,000 reads#
Scale <- 10000/colSums(Final[,-1])

## Create filter for genes expressed in 20 or more cells and filter data by it ##
percell <- rowSums(Final[,-1] != 0)
Final <- Final[percell >= 20, ]

## read the cell metadata and create dictionary with cluster names   ##
## and barcode names (need to loop through barcodes to correct them) ##

#Read in cell metadata to extract cell identities#
ID <- read.table("GSE129788/GSE129788_Supplementary_meta_data_Cell_Types_Etc.txt.gz")
#Create dictionary of cluster names#
dict <- ID$V4[-1:-2]

#Loop over every dictionary entry and name the dictionary entry specifically cutting the string from the right to create usable barcodes#
for (i in 1:length(ID$V4[-1:-2])){
  if(nchar(as.character(ID$V1[-1:-2])[i]) == 49) {
  names(dict)[i] <- substrRight(as.character(ID$V1[-1:-2]), 19)[i]
  }else{
    names(dict)[i] <- substrRight(as.character(ID$V1[-1:-2]), 18)[i]
  }
  print(i)
}

#Take data and transform it so genes are columns and cells are rows#
all_global_cells <- data.frame(t(Final), stringsAsFactors = FALSE)
#Name columns after first row and then remove it#
colnames(all_global_cells) <- as.character(unlist(all_global_cells[1,]))
all_global_cells <- all_global_cells[-1,]

## Looping through columns, multiply the values by their scaling factor and log transform the data to create final normalised data#
for(i in 1:ncol(all_global_cells)){
  all_global_cells[,i] <- as.numeric(as.character(all_global_cells[,i]))
  all_global_cells[,i] <- all_global_cells[,i] * Scale
  all_global_cells[,i] <- log(all_global_cells[,i] + 1)
  print(i)
}

#Create iden column with cell identities#
all_global_cells$iden <- dict[rownames(all_global_cells)]

#Leave the raw data directory#
setwd("../")

#Create an Output directory and write the datafile generated into that file to skip stage 1 next time#
ifelse(!dir.exists(file.path(getwd(), "Outputs")), dir.create(file.path(getwd(), "Outputs")), FALSE)
fwrite(all_global_cells, "final_data.csv", row.names = TRUE)

### ONE-SIDED WILCOXON TEST ###################################################################################

#read back in data if starting here#
all_global_cells <- data.frame(fread("Outputs/final_data.csv"))
rownames(all_global_cells) <- all_global_cells$V1
all_global_cells$V1 = NULL

#create wil object to run through the pipeline, make sure it is dataframe and then create iden and gene variables to filter data by in the loop#
wil <- all_global_cells
wil <- data.frame(wil)

#Create iden - list of unique cell identities to loop over#
iden <- sort(unique(wil$iden))

#write table of number of cells per cell identity#
write.csv(table(wil$iden), paste("Outputs/cell_numbers_Global.csv", sep = ""))

#Precreate dataframes for p, q, fc, pct.in, pct.rest values#
p <- data.frame("gene" = colnames(wil)[-ncol(wil)], stringsAsFactors = FALSE)
fc <- data.frame("gene" = colnames(wil)[-ncol(wil)], stringsAsFactors = FALSE)
percent_in <- data.frame("gene" = colnames(wil)[-ncol(wil)], stringsAsFactors = FALSE)
percent_rest <- data.frame("gene" = colnames(wil)[-ncol(wil)], stringsAsFactors = FALSE)
q <- data.frame("gene" = colnames(wil)[-ncol(wil)], stringsAsFactors = FALSE)

#Loop over every gene/column apart from the final 'iden' column#
for (b in 1:(ncol(wil)-1)){
  
  #subset the reads for this gene and the cell identities#
  dd <- wil[,c(b, ncol(wil))]
  colnames(dd) <- c("reads", "iden")
  
  #Loop through each cell identity#
  for (c in 1:length(iden)){
    #extract the reads from identity of interest#
    interest <- as.numeric(as.character(dd[dd$iden == iden[c],]$reads))
    #extract the reads from the other identities#
    rest <- as.numeric(as.character(dd[dd$iden != iden[c],]$reads))
    #Run the Wilcoxon test, one-sided#
    W <- wilcox.test(interest, rest, exact = FALSE, alternative = "greater")
    #Update the cell in the precreated database with the p value#
    p[b,c+1] <- as.numeric(W$p.value)
    #Divide Mean interest by Mean rest to create FC value#
    fc[b,c+1] <- mean(interest)/mean(rest)
    #divide number of non-zero cells by total number of cells to create percent values#
    percent_in[b,c+1] <- sum(interest != 0)/ length(interest)
    percent_rest[b,c+1] <- sum(rest != 0)/ length(rest)
  }
  #Print b as a progress counter#
  print(b)
}

#Change colnames to identity values for p, pct.in and pct.rest and save these files#
colnames(p) <- c("gene", iden)
fwrite(p, paste("Outputs/Ximerakis_p.csv", sep=""))
colnames(percent_in) <- c("gene", iden)
fwrite(percent_in, paste("Outputs/Ximerakis_percent_in.csv", sep=""))
colnames(percent_rest) <- c("gene", iden)
fwrite(percent_rest, paste("Outputs/Ximerakis_percent_rest.csv", sep=""))

#Change colnames to identity values#
colnames(fc) <- c("gene", iden)
#set infinite FC values to the max for that identity types#
for(x in 2:ncol(fc)){
  m = max(fc[is.finite(fc[,x]),x])
  fc[is.infinite(fc[,x]),x] = m
}
#Save this file#
fwrite(fc, paste("Outputs/Ximerakis_fc.csv", sep=""))

# adjust p value horizontally using BH correcton and update this to the q dataframe#
for (x in 1:nrow(p)){
  q[x,2:ncol(p)] <- p.adjust(as.numeric(p[x,2:ncol(p)]), method = "BH")
}

#Change colnames to identity values and save the file#
colnames(q) <- c("gene", iden)
fwrite(q, paste("Outputs/Ximerakis_q.csv", sep=""))

#Set allele sex biases to loop over#
sex <- c("P","M","ALL")

# #Loop over PEGs MEGS and all IGs#
for (s in c(1:length(sex))){
  #set a second imprinted gene list to subset#
  IIGG <- IG
  #For Pegs and Megs reduce the list#
  if(sex[s] %in% c("P","M")){
    IIGG <- IIGG[IIGG$Sex == sex[s],]
  }
  
  #Set up a directory for the sex subset#
  ifelse(!dir.exists(file.path(paste(getwd(), "/Outputs/", sep = ""), sex[s])), dir.create(file.path(paste(getwd(), "/Outputs/", sep = ""), sex[s])), FALSE)
  
  #define dataframes for files to later save#
  Fish <- data.frame("Identity" = colnames(q[,-1]), stringsAsFactors = FALSE)
  Genelist <- data.frame("Identity" = colnames(q[,-1]), stringsAsFactors = FALSE)
  DEGs <- data.frame()
  IGs <- data.frame()
  
  #loop through identity groups (columns in the p/fc/q etc. files)#
  for (e in 2:(ncol(q))){
    ORA <- data.frame(gene = q$gene, p = p[,e], q = q[,e], fc = fc[,e], pct.in = percent_in[,e], pct.rest = percent_rest[,e], stringsAsFactors = FALSE)
    
    #filter ORA by significant q values and fc limit#
    ORA <- ORA[ORA$q <= 0.05 & ORA$fc >= 2,]
    
    #create repeat column of identity name#
    ORA$Identity = colnames(q)[e]
    
    #Add rows to DEGS - all differentialy expressed genes for that tissue and the total number to Fish#
    DEGs <- rbind(DEGs, ORA)
    Fish[e-1,2] = nrow(ORA)
    
    #Filter ORA for imprinted genes only and add that to IGs file and the total number to Fish#
    ig <- ORA %>% filter(gene %in% IIGG$Gene)
    IGs <- rbind(IGs, ig)
    Fish[e-1,3] = nrow(ig)
    
    #Add to the IG genelist, only if there are significant genes for that tissue#
    if (nrow(ig) > 0){
      for (z in 1:nrow(ig)){
        Genelist[e-1, z+1] <- as.character(ig$gene[z])
      }
    }
  }
  
  #add colnames to Fish and save all the files generated other than Fish#
  colnames(Fish)<- c("Identity","UpReg", "IG")
  fwrite(Genelist, paste("Outputs/", sex[s], "/genelist.csv", sep =""))
  fwrite(DEGs, paste("Outputs/", sex[s], "/DEGs.csv", sep =""))
  fwrite(IGs, paste("Outputs/", sex[s], "/Imprinted_DEGs.csv", sep =""))
  
  ### OVER REPRESENTATION ANALYSIS (ORA) ########################################################################
  
  #Create an identity group filter based on having a minimum of 5 imprinted genes upregulated#
  tissue_ORA <- Fish$Identity[Fish$IG >= (as.numeric(sum(q$gene %in% IIGG$Gene))/20)]
  
  #As long as one cell identity has 5 or more IGs, run a Fisher's Exact test#  
  if(length(tissue_ORA) > 0){
    #For every identity, check if it is in the tissue filter#
    for (c in 1:nrow(Fish)){
      if(Fish$Identity[c] %in% tissue_ORA){
        #Create the 2x2 matrix for the fisher's exact test - no. IG in group, no. of IG left over, no. of UpRegulated genes in group minus no. of IGs, all genes left over
        test <- data.frame(gene.interest=c(as.numeric(Fish[c,3]),as.numeric(sum(q$gene %in% IIGG$Gene) - Fish[c,3])), gene.not.interest=c((as.numeric(Fish[c,2]) - as.numeric(Fish[c,3])),as.numeric(nrow(q) - Fish[c,2])- as.numeric(sum(q$gene %in% IIGG$Gene) - Fish[c,3])))
        row.names(test) <- c("In_category", "not_in_category")
        f <- fisher.test(test, alternative = "greater")
        #Update Fish with 
        Fish[c,4] <- f$p.value
      }
    }
    names(Fish)[length(names(Fish))] <- "ORA_p"
    
    ## Add a new column to Fish with adjusted Fisher p values (bonferroni correction)##
    Fish$Adjust_ORA <- p.adjust(Fish$ORA_p, method = "bonferroni")
    names(Fish)[length(names(Fish))] <- "ORA_q"
  }
  
  ### MEAN FOLD CHANGE #########################################################################################  
  
  ##Calculate mean fold change for upregulated imprinted genes in each identity group#
  igs <- (IGs %>% group_by(Identity) %>% summarise(mean = mean(fc)))
  
  #Input tissues without Imprinted Genes as 0 in igs#
  if (length(unique(DEGs$Identity)) != length(unique(IGs$Identity))){
    leftout <- data.frame("Identity" = unique(DEGs$Identity)[!(unique(DEGs$Identity) %in% unique(IGs$Identity))])
    leftout$mean = 0
    igs <- rbind(igs, leftout)
  }
  
  #Merge Fish with igs to have a Mean Fold change imprinted gene column#
  Fish <- merge(Fish, igs, by = "Identity")
  names(Fish)[length(names(Fish))] <- "Mean FC IG"
  
  ##Calculate mean fold change for the rest of the upregulated genes per tissue and update a column in Fish## 
  rest <- DEGs[!(DEGs$gene %in% IIGG$Gene),] %>% group_by(Identity) %>% summarise("mean" = mean(fc))
  
  #Merge Fish with rest to have a Mean Fold change Rest of genes column#
  Fish <- merge(Fish, rest, by = "Identity")
  names(Fish)[length(names(Fish))] <- "Mean FC Rest"
  
  ### GENE SET ENRICHMENT ANALYSIS (GSEA) ########################################################################  
  
  #Create list of identities that fulfill the criteria for GSEA - more than 10% of imprinted genes present and a IG FC higher than Rest FC#
  tissue_GSEA <- Fish$Identity[(Fish$`Mean FC IG` >= Fish$`Mean FC Rest` & Fish$IG >= 15)]
  
  ##If there are tissues in tissue_GSEA run a GSEA analysis for IGs in each of those tissues##
  if(length(tissue_GSEA) > 0){
    ifelse(!dir.exists(file.path(paste(getwd(), "/Outputs/", sex[s], sep = ""), "GSEA")), dir.create(file.path(paste(getwd(), "/Outputs/", sex[s], sep = ""), "GSEA")), FALSE)
    for(f in 1:length(tissue_GSEA)){
      #filter DEGs for the tissue selected#
      daa <- DEGs %>% filter(DEGs$Identity == tissue_GSEA[f])
      #create log transformed fc values for DEGs#
      file <- log2(daa$fc)
      #replace infinity values with max values and name the file with gene names#
      file[is.infinite(file)] <- max(file[is.finite(file)])
      file <- set_names(file, daa$gene)
      #create imprinted gene list to use for GSEA#
      ig <- as.character(IIGG$Gene)
      #save the graph from the GSEA as a pdf#
      pdf(paste("Outputs/", sex[s],"/GSEA/",gsub("[^A-Za-z0-9 ]","",tissue_GSEA[f]), "_GSEA.pdf", sep=""))
      #Add GSEA p value to Fish#
      Fish[Fish$Identity == tissue_GSEA[f],8] <- gsea(file, ig)
      #Save PDF#
      dev.off()
    }
    
    names(Fish)[length(names(Fish))] <- "GSEA_p"
    
    #Adjust the GSEA p values using bonferroni as new column in Fish#
    Fish$Adjust_GSEA <- p.adjust(Fish$GSEA_p, method = "bonferroni")
    names(Fish)[length(names(Fish))] <- "GSEA_q"
  }
  
  ### IMPRINTED GENE TOP TISSUE EXPRESSION ######################################################################    
  
  #Filter Main data for Imprinted Genes and create Identity column#
  D <- data.frame(wil[,colnames(wil) %in% as.character(IIGG$Gene)])
  D$iden <- wil$iden
  #Gather this data and group by gene, identity and get per gene per identity read averages#
  D <- D %>% gather(gene, reads, -iden) %>% group_by(gene, iden) %>% summarise("avg" = mean(as.numeric(reads)))
  #Gather fc file by iden and value and filter that for imprinted genes#
  FC <- fc %>% gather(iden, fc, -gene) %>% filter(gene %in% IIGG$Gene)
  #Join the two datasets#
  D2 <- left_join(D, FC, by = c("gene","iden"))
  
  #create u with the tissue with max expression for each IG and save that file#
  u <- D2 %>% group_by(gene) %>% filter(gene %in% IIGG$Gene & (avg == max(avg) & max(avg) > 0))
  fwrite(u, paste("Outputs/", sex[s], "/IG_top_expressed.csv", sep =""))
  #update a Fish column with the number of IGs with top expression in that tissue#
  u <- u %>% group_by(iden) %>% summarise("Top_Tissue_IGs" = n())
  Fish <- merge(Fish, u, by.x = "Identity", by.y = "iden", all = TRUE)
  
  fwrite(Fish, paste("Outputs/", sex[s],"/Enrichment_Analysis.csv", sep =""))
  
##### Calculate Avg Normalised Expression across identity groups ########

#Create D again - the dataset filtered for imprinted genes and iden readded#
D <- data.frame(wil[,colnames(wil) %in% as.character(IIGG$Gene)])
D$iden <- wil$iden
D <- D %>% gather(gene, reads, -iden)

#Create dataframe to save average expression values to#
avg_expr <- data.frame(iden <- unique(as.character(D$iden)))

#Create rest which includes all other genes#
rest <- data.frame(wil[,!(colnames(wil) %in% as.character(IIGG$Gene))])

#Loop through each identity groups and calculate mean normalised expression for imprinted genes and the rest#
for(i in 1:length(unique(D$iden))){
  #extract the reads from identity of interest#
  values <- as.numeric(as.character(D[D$iden == iden[i],]$reads))
  #take mean value and save it to avg_expr
  avg_expr[i,2] <- mean(values)
  a <- rest[rest$iden == iden[i],]
  a <- a %>% gather("gene", "reads", -iden)
  avg_expr[i,3] <- mean(a$reads)
}

colnames(avg_expr) <- c("identity", "mean_exp_IG", "mean_exp_rest_of_genes")

write.csv(avg_expr, paste("Outputs/Xim_mean_norm_expr.csv", sep =""))

#### STAGE 3 - VISUALISATION DOTPLOT for NENDC ########################################################################################################

#Arrange Fish by over-representation significance, take the identity variable as an order value#
Fish <- Fish %>% arrange(Fish$ORA_p)
order <- Fish$Identity

#Filter original IG list with those upregualted in neuroendocrine cells#
IG2 <- IIGG[IIGG$Gene %in% IGs$gene[IGs$Identity == "NendC"],]
#Arrange IGs by the chromosomal order#
IG2 <- IG2 %>% arrange(IG2$Order)

#Filter IGs for Paternally expressed genes (PEGs) only and create Pat using the PEG only filter#
pat <- IG2 %>% filter(Sex == "P")
Pat <- D2 %>% filter(gene %in% pat$Gene)
Pat$fc <- log2(Pat$fc+1)

#Filter IGs for maternally expressed genes (MEGs) only and create Mat using the MEG only filter#
mat <- IG2 %>% filter(Sex == "M" | Sex == "I")
Mat <- D2 %>% filter(gene %in% mat$Gene)
Mat$fc <- log2(Mat$fc+1)

### Create Function to align the legend of the dotplot to the centre ###
align_legend <- function(p, hjust = 0.5)
{
  # extract legend
  g <- cowplot::plot_to_gtable(p)
  grobs <- g$grobs
  legend_index <- which(sapply(grobs, function(x) x$name) == "guide-box")
  legend <- grobs[[legend_index]]
  
  # extract guides table
  guides_index <- which(sapply(legend$grobs, function(x) x$name) == "layout")
  
  # there can be multiple guides within one legend box  
  for (gi in guides_index) {
    guides <- legend$grobs[[gi]]
    
    # add extra column for spacing
    # guides$width[5] is the extra spacing from the end of the legend text
    # to the end of the legend title. If we instead distribute it by `hjust:(1-hjust)` on
    # both sides, we get an aligned legend
    spacing <- guides$width[5]
    guides <- gtable::gtable_add_cols(guides, hjust*spacing, 1)
    guides$widths[6] <- (1-hjust)*spacing
    title_index <- guides$layout$name == "title"
    guides$layout$l[title_index] <- 2
    
    # reconstruct guides and write back
    legend$grobs[[gi]] <- guides
  }
  
  # reconstruct legend and write back
  g$grobs[[legend_index]] <- legend
  g
}

dot <- ggplot(D2, aes(x=iden, y=gene, color=ifelse(fc == 0, NA, fc), size=ifelse(avg==0, NA, avg))) + 
  geom_point(data = Pat,aes(color = ifelse(fc == 0, NA, fc)), alpha = 0.8) +
  scale_color_gradientn(colours = c("grey95","grey90","blue","darkblue","midnightblue"), na.value="midnightblue", values = c(0, 0.2, 0.4, 0.6, 0.8 ,1), limits = c(0,4)) +
  labs(color = "Log2FC vs\nBackground\n(PEGs)")+
  new_scale_color()+
  geom_point(data = Mat, aes(color = ifelse(fc == 0, NA, fc)), alpha = 0.8) +
  scale_color_gradientn(colours = c("grey95","grey90","orange","red","darkred"), na.value="darkred", values = c(0, 0.2, 0.4, 0.6, 0.8 ,1), limits = c(0,4)) +
  theme_classic() +
  theme(axis.text.x = element_text(angle = 90, face = "italic"), axis.title.x = element_text(angle = 180), axis.title.y.right = element_text(angle = 90), axis.text.y = element_text(angle = 180), legend.title.align=0.5) +
  scale_size_continuous(limits = c(0,max(D2$avg)))+
  scale_x_discrete(limits = order, position = "top") +
  scale_y_discrete(limits = (IG2$Gene))+
  guides(size = guide_legend(order = 1))+
  coord_flip()+
  labs(x = "Cell Lineage Identity (Whole Brain - Ximerakis et al., 2019)", y = "Imprinted Gene", size = "Normalised\nMean\nExpression", color = "Log2FC vs\nBackground\n(MEGs)")

pdf("Outputs/Ximerakis_Cell_lineage_DOTPLOT.pdf", paper= "a4r",  width = 28, height = 18)
ggdraw(align_legend(dot))
dev.off()

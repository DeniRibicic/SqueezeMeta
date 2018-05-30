
#-- Generic paths

#$installpath="";
$databasepath="/media/disk6/fer/Projects/squeezeM/squeezeM/db"
$extdatapath="$installpath/data";
$scriptdir="$installpath/scripts";   #-- Scripts directory

#-- Paths relatives to the project

$projectname="";
$basedir=".";
$datapath="$basedir/$projectname/data";			#-- Directory containing all datafiles
$resultpath="$basedir/$projectname/results";		#-- Directory for storing results
$tempdir="$basedir/$projectname/temp";			#-- Temp directory
%bindirs=("maxbin","$resultpath/maxbin","metabat2","$resultpath/metabat2");	#-- Directories for bins

#-- Result files

$mappingfile="$datapath/00.$projectname.samples";       #-- Mapping file (samples -> fastq)
$contigsfna="$resultpath/01.$projectname.fasta";        #-- Contig file from assembly
$contigslen="$resultpath/01.$projectname.lon";
$rnafile="$resultpath/02.$projectname.rnas";            #-- RNAs from barrnap
$gff_file="$resultpath/03.$projectname.gff";            #-- gff file from prodigal
$aafile="$resultpath/03.$projectname.faa";              #-- Aminoacid sequences for genes
$ntfile="$resultpath/03.$projectname.fna";              #-- Nucleotide sequences for genes
$daafile="$resultpath/04.$projectname.daa";             #-- Diamond result
$taxdiamond="$resultpath/04.$projectname.nr.diamond";	#-- Diamond result
$cogdiamond="$resultpath/04.$projectname.eggnog.diamond";               #-- Diamond result, COGs
$keggdiamond="$resultpath/04.$projectname.kegg.diamond";                #-- Diamond result, KEGG
$pfamhmmer="$resultpath/05.$projectname.pfam.hmm";      #-- Hmmer result for Pfam
$fun3tax="$resultpath/06.$projectname.fun3.tax";	#-- Fun3 annotations, KEGG
$fun3kegg="$resultpath/07.$projectname.fun3.kegg";	#-- Fun3 annotations, KEGG
$fun3cog="$resultpath/07.$projectname.fun3.cog";	#-- Fun3 annotation, COGs
$fun3pfam="$resultpath/07.$projectname.fun3.pfam";	#-- Fun3 annotation, Pfams
$allorfs="$resultpath/08.$projectname.allorfs";         #-- From summary_contigs.pl, allorfs file
$alllog="$resultpath/08.$projectname.contiglog";	#-- From summary_contigs.pl, contiglog file (formerly alllog file)
$rpkmfile="$resultpath/09.$projectname.bedcount";       #-- From mapbamsamples.pl, rpkm counts for all samples
$coveragefile="$resultpath/09.$projectname.coverage";   #-- From mapbamsamples.pl, rpkm counts for all samples
$contigcov="$resultpath/09.$projectname.contigcov";     #-- From mapbamsamples.pl, coverages of  for all samples
$mcountfile="$resultpath/10.$projectname.mcount";	#-- From mcount.pl, abundances of all taxa
$mergedfile="$resultpath/12.$projectname.mergedtable";	#-- GEN TABLE FILE
$bintax="$resultpath/15.$projectname.bintax";           #-- From addtax2.pl
$bincov="$resultpath/17.$projectname.bincov";           #-- Coverage of bins, from getbins.pl
$bintable="$resultpath/17.$projectname.bintable";       #-- Mapping of contigs in bins, from getbins.pl
$contigsinbins="$resultpath/18.$projectname.contigsinbins";
$contigtable="$resultpath/18.$projectname.contigtable"; #-- From getcontigs.pl, CONTIGS TABLE

#-- Datafiles

$coglist="$extdatapath/coglist.txt";    #-- COG equivalence file (COGid -> Function -> Functional class)
$kegglist="$extdatapath/keggfun2.txt";  #-- KEGG equivalence file (KEGGid -> Function -> Functional class)
$pfamlist="$extdatapath/pfam.dat";      #-- PFAM equivalence file
$taxlist="$extdatapath/alltaxlist.txt"; #-- Tax equivalence file 
$nr_db="$databasepath/nr.dmnd";
$cog_db="$databasepath/eggnog";
$kegg_db="$databasepath/keggdb";
$lca_db="$databasepath/LCA_tax/taxid.db";
$bowtieref="$datapath/$projectname.bowtie";                     #-- Contigs formateados para Bowtie
$pfam_db="$databasepath/Pfam-A.hmm";

#-- Variables

$evalue=1e-03;
$miniden=50;
$nocog=0;
$nokegg=0;
$nopfam=0;
$nobins=0;

#-- External software

$metabat_soft="$installpath/bin/metabat2";
$maxbin_soft="$installpath/bin/run_MaxBin.pl";
$spades_soft="$installpath/bin/spades.py";
$barrnap_soft="$installpath/bin/barrnap";
$bowtie2_build_soft="$installpath/bin/bowtie2-build";
$bowtie2_x_soft="$installpath/bin/bowtie2";
$bedtools_soft="$installpath/bin/bedtools";   #-- IMPORTANT! Needs version <0.24    
$diamond_soft="$installpath/bin/diamond";
$hmmer_soft="$installpath/bin/hmmsearch";
$megahit_soft="$installpath/bin/megahit";
$prinseq_soft="$installpath/bin/prinseq-lite.pl";
$prodigal_soft="$installpath/bin/prodigal";
$cdhit_soft="$installpath/bin/cd-hit-est";
$toamos_soft="$installpath/bin/toAmos";
$minimus2_soft="$installpath/bin/minimus2";
$checkm_soft="$installpath/bin/checkm";


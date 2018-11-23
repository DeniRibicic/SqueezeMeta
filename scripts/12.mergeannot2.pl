#!/usr/bin/perl

#-- Part of SqueezeMeta distribution. 01/05/2018 Original version, (c) Javier Tamames, CNB-CSIC
#-- Creates gene table putting together all the information from previous steps

use strict;
use Tie::IxHash;
use Cwd;

$|=1;

my $pwd=cwd();
my $project=$ARGV[0];
$project=~s/\/$//; 

do "$project/SqueezeMeta_conf.pl";

#-- Configuration variables from conf file

our($datapath,$resultpath,$coglist,$kegglist,$aafile,$ntfile,$rnafile,$fun3tax,$alllog,$fun3kegg,$fun3cog,$fun3pfam,$rpkmfile,$coveragefile,$mergedfile);

my $seqsinfile=0;     # Put sequences in the output table (0=no, 1=yes)

my(%orfdata,%contigdata,%cog,%kegg,%datafiles,%mapping);
tie %orfdata,"Tie::IxHash";

	#-- Reading data for COGs (names, pathways)

open(infile1,$coglist) || warn "Missing COG equivalence file\n";
print "Reading COG list\n";
while(<infile1>) {
	chomp;
	next if(!$_ || ($_=~/\#/));
	my @t=split(/\t/,$_);
	$cog{$t[0]}{fun}=$t[1];
	$cog{$t[0]}{path}=$t[2]; 
            }
close infile1;

	#-- Reading data for KEGGs (names, pathways)

open(infile2,$kegglist) || warn "Missing KEGG equivalence file\n";
print "Reading KEGG list\n";
while(<infile2>) {
	chomp;
	next if(!$_ || ($_=~/\#/));
	my @t=split(/\t/,$_);
	$kegg{$t[0]}{name}=$t[1];
	$kegg{$t[0]}{fun}=$t[2];
	$kegg{$t[0]}{path}=$t[3];
	}
close infile2;

	#-- Reading aa sequences 

open(infile3,$aafile) || die "I need the protein sequences from the prediction\n";
print "Reading aa sequences\n";
my($thisorf,$aaseq);
while(<infile3>) {
	chomp;
	if($_=~/^\>([^ ]+)/) {		#-- If we are reading a new ORF, store the data for the last one
		if($aaseq) { 
			$orfdata{$thisorf}{aaseq}=$aaseq; 
			$orfdata{$thisorf}{length}=(length $aaseq)+1; 
			}
		$thisorf=$1;
		$aaseq="";
		}
	else { $aaseq.=$_; }		#-- Otherwise store the sequence of the current	      
	}
close infile3;
if($aaseq) { $orfdata{$thisorf}{aaseq}=$aaseq; }


	#-- Reading RNAs

open(infile4,$rnafile) || warn "I need the RNA sequences from the prediction\n";
print "Reading RNA sequences\n";
my($thisrna,$rnaseq);
while(<infile4>) {
	chomp;
	if($_=~/^\>/) {			#-- If we are reading a new ORF, store the data for the last one
		$_=~s/^\>//;
		my @mt=split(/\t/,$_);
		if($rnaseq) { 
			$orfdata{$thisrna}{ntseq}=$rnaseq;
			$orfdata{$thisrna}{length}=(length $rnaseq)+1;
			}
		$thisrna=$mt[0];
		my @l=split(/\s+/,$_,2);
		my @ll=split(/\;/,$l[1]);
		my $rnaname=$ll[0];
		$orfdata{$thisorf}{name}=$rnaname;  
		$rnaseq="";
		}
	else { $rnaseq.=$_; }		#-- Otherwise store the sequence of the current		      
}
close infile4;
if($rnaseq) { 
	$orfdata{$thisrna}{ntseq}=$rnaseq; 
	$orfdata{$thisrna}{length}=(length $rnaseq)+1;
	}

	#-- Reading taxonomic assignments

open(infile5,"$fun3tax.wranks") || warn "Cannot open allorfs file $fun3tax.wranks\n";
print "Reading ORF information\n";
while(<infile5>) { 
	chomp;
	next if(!$_ || ($_=~/\#/));
	my @t=split(/\t/,$_);
	my $mdat=$t[1];
	$mdat=~s/\;$//;
	$orfdata{$t[0]}{tax}=$mdat;
	$datafiles{'allorfs'}=1;
}
close infile5;

	#-- Reading nt sequences for calculating GC content

my($ntorf,$ntseq,$gc);
open(infile6,$ntfile) || warn "Cannot open nt file $ntfile\n";
print "Calculating GC content for genes\n";
while(<infile6>) { 
	chomp;
	if($_=~/^\>([^ ]+)/) {			#-- If we are reading a new ORF, store the data for the last one
		if($ntseq) { 
		$gc=gc_count($ntseq,$ntorf);
		$orfdata{$ntorf}{gc}=$gc;
		}
	$ntorf=$1;
	$ntseq="";
	}
	else { $ntseq.=$_; }		#-- Otherwise store the sequence of the current			      
}
close infile6;
if($ntseq) { $gc=gc_count($ntseq); }		#-- Last ORF in the file
$orfdata{$ntorf}{gc}=$gc; 
$datafiles{'gc'}=1;

	#-- Reading nt sequences for calculating GC content for RNAs

($ntorf,$ntseq,$gc)="";
open(infile7,$rnafile) || warn "Cannot open RNA file $rnafile\n";
print "Calculating GC content for RNAs\n";
while(<infile7>) { 
	chomp;
	if($_=~/^\>/) {			#-- If we are reading a new ORF, store the data for the last one
		$_=~s/^\>//;
		my @mt=split(/\t/,$_);
		if($ntseq) { 
			$gc=gc_count($ntseq,$ntorf);
			$orfdata{$ntorf}{gc}=$gc; 
		}
	$ntorf=$mt[0];
	$ntseq="";
                      }
	else { $ntseq.=$_; }		#-- Otherwise store the sequence of the current		      
}
close infile7;
if($ntseq) { $gc=gc_count($ntseq); }
$orfdata{$ntorf}{gc}=$gc; 

	#-- Reading taxonomic assignment and disparity for the contigs

open(infile8,$alllog) || warn "Cannot open contiglog file $alllog\n";
print "Reading contig information\n";
while(<infile8>) { 
	chomp;
	next if(!$_ || ($_=~/\#/));
	my @t=split(/\t/,$_);
	$contigdata{$t[0]}{tax}=$t[1]; 
	if($t[3]=~/Disparity\: (.*)/i) { $contigdata{$t[0]}{chimerism}=$1; }
	$datafiles{'alllog'}=1;
}
close infile8;

	#-- Reading KEGG annotations for the ORFs

open(infile9,$fun3kegg) || warn "Cannot open fun3 KEGG annotation file $fun3kegg\n";
print "Reading KEGG annotations\n";
while(<infile9>) {
	chomp;
	next if(!$_ || ($_=~/\#/));
	my($gen,$f,$ko)=split(/\t/,$_);
	if($f) { 
		$orfdata{$gen}{kegg}=$f; 
		$orfdata{$gen}{name}=$kegg{$f}{name};	#-- Name of the gene (symbol), taken from KEGG
	}		
	if($ko) { $orfdata{$gen}{keggaver}=1; }	#-- Best aver must be the same than best hit, we just mark if there is best aver or not 
	$datafiles{'kegg'}=1;
}
close infile9;          
  
	#-- Reading COG annotations for the ORFs

open(infile10,$fun3cog) || warn "Cannot open fun3 COG annotation file $fun3cog\n";;
print "Reading COGs annotations\n";
while(<infile10>) { 
	chomp;
	next if(!$_ || ($_=~/\#/));
	my($gen,$f,$co)=split(/\t/,$_);
	if($f) { $orfdata{$gen}{cog}=$f; }
	if($co) { $orfdata{$gen}{cogaver}=1; } #-- Best aver must be the same than best hit, we just mark if there is best aver or not
	$datafiles{'megancog'}=1;
}
close infile10;            
  
	#-- Reading Pfam annotations for the ORFs

open(infile11,$fun3pfam) || warn "Cannot open fun3 Pfam annotation file $fun3cog\n";;
print "Reading Pfam annotations\n";
while(<infile11>) { 
	chomp;
	next if(!$_ || ($_=~/\#/));
	my($gen,$co)=split(/\t/,$_);
	if($co) { $orfdata{$gen}{pfam}=$co; }
	$datafiles{'pfam'}=1;
}
close infile11;            			       
  
	#-- Reading RPKM values for the ORFs in the different samples

open(infile12,$rpkmfile) || warn "Cannot open mapping file $rpkmfile\n";
print "Reading RPKMs\n";
while(<infile12>) {
	chomp;
	next if(!$_ || ($_=~/\#/));
	my($orf,$fpkm,$raw,$idfile)=split(/\t/,$_);
	$mapping{$idfile}{$orf}{fpkm}=$fpkm;		#-- RPKM values
	$mapping{$idfile}{$orf}{raw}=$raw; 		#-- Raw counts
	#  print "$idfile*$orf*$fpkm\n"
}
close infile12;	     
  
	#-- Reading coverage values for the ORFs in the different samples

open(infile13,$coveragefile) || warn "Cannot open coverage file $rpkmfile\n";
print "Reading coverages\n";
while(<infile13>) {
	chomp;
	next if(!$_ || ($_=~/\#/));
	my($orf,$raw,$coverage,$idfile)=split(/\t/,$_);
	$mapping{$idfile}{$orf}{coverage}=$coverage;	#-- Coverage values
	#  print "$idfile*$orf*$fpkm\n"
}
close infile13;	     
  
	#-- CREATING GEN TABLE

print "Creating table\n";
open(outfile1,">$mergedfile") || die "I need an output file\n";

	#-- Headers

print outfile1 "#--Created by $0, ",scalar localtime,"\n";
print outfile1 "ORF\tCONTIG ID\tLENGTH\tGC perc\tGENNAME\tTAX ORF\tKEGG ID\tKEGGFUN\tKEGGPATH\tCOG ID\tCOGFUN\tCOGPATH\tPFAM";
foreach my $cnt(sort keys %mapping) { print outfile1 "\tRPKM $cnt"; }
foreach my $cnt(sort keys %mapping) { print outfile1 "\tCOVERAGE $cnt"; }
foreach my $cnt(sort keys %mapping) { print outfile1 "\tRAW COUNTS $cnt"; }
if($seqsinfile) { print outfile1 "\tAASEQ"; }
print outfile1 "\n";

	#-- ORF data

foreach my $orf(sort keys %orfdata) {
	my($cogprint,$keggprint);
	my $ctg=$orf;
	$ctg=~s/\_\d+$//;
	$ctg=~s/\_RNA\d+$//;
	# next if((!$mapping{'s22'}{$orf}{'fpkm'}) && (!$mapping{'st8'}{$orf}{'fpkm'})); 
	my $funcogm=$orfdata{$orf}{cog};
	my $funkeggm=$orfdata{$orf}{kegg};
	if($orfdata{$orf}{cogaver}) { $cogprint="$funcogm*"; } else { $cogprint="$funcogm"; }
	if($orfdata{$orf}{keggaver}) { $keggprint="$funkeggm*"; } else { $keggprint="$funkeggm"; }
	printf outfile1 "$orf\t$ctg\t$orfdata{$orf}{length}\t%.2f\t$orfdata{$orf}{name}\t$orfdata{$orf}{tax}\t$keggprint\t$kegg{$funkeggm}{fun}\t$kegg{$funkeggm}{path}\t$cogprint\t$cog{$funcogm}{fun}\t$cog{$funcogm}{path}\t$orfdata{$orf}{pfam}",$orfdata{$orf}{gc};

	#-- Abundance values

	foreach my $cnt(sort keys %mapping) { print outfile1 "\t$mapping{$cnt}{$orf}{'fpkm'}"; }
	foreach my $cnt(sort keys %mapping) { print outfile1 "\t$mapping{$cnt}{$orf}{'coverage'}"; }
	foreach my $cnt(sort keys %mapping) { print outfile1 "\t$mapping{$cnt}{$orf}{'raw'}"; }

	#-- aa sequences (if requested)

	if($seqsinfile) { print outfile1 "\t$orfdata{$orf}{aaseq}"; }
	print outfile1 "\n";
}
close outfile1;

print "Output created in $mergedfile\n";


#------------------- GC calculation

sub gc_count {
 my $seq=shift;
 my $corf=shift;
 my @m=($seq=~/G|C/gi);
 my $lseq=length $seq;
 if(!$lseq) { print "Zero length sequence found for $corf\n"; next; }
 my $gc=(($#m+1)/length $seq)*100;
 return $gc;
              }



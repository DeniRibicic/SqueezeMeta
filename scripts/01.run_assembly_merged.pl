#!/usr/bin/perl

#-- Part of squeezeM distribution. 28/08/2018 for version 0.3.0, (c) Javier Tamames, CNB-CSIC
#-- Runs assembly programs (currently megahit or spades) for several metagenomes that will be merged in the next step (merged mode).
#-- Uses prinseq to filter out contigs by length (excluding small ones).

use strict;
use Cwd;

$|=1;

my $pwd=cwd();
my $project=$ARGV[0];

do "$project/squeezeM_conf.pl";

#-- Configuration variables from conf file

our($datapath,$assembler,$outassembly,$mappingfile,$tempdir,$megahit_soft,$assembler_options,$numthreads,$spades_soft,$canu_soft,$prinseq_soft,$mincontiglen,$resultpath,$contigsfna,$contigslen,$format);

#-- Read all the samples and store file names

my %ident;
my %samplefiles;

open(infile1,$mappingfile) || die "Cannot open samples file $mappingfile\n";
while(<infile1>) {
	chomp;
	next if(!$_ || ($_=~/^\#/));
	my($sample,$file,$iden)=split(/\t/,$_);
	$ident{$file}=$iden;
	$samplefiles{$sample}{$file}=1;
	}
close infile1;

#-- Start working with samples, one at the time

	#-- Prepare files for the assembly

my($par1name,$par2name,$command);
foreach my $thissample(sort keys %samplefiles) {
	print "Working for sample $thissample\n";
	my $cat1="cat ";
	my $cat2="cat ";
	foreach my $thisfile(sort keys %{ $samplefiles{$thissample} }) {
		system("rm $tempdir/par*fastq*");
		if($thisfile=~/gz$/) { $par1name="$tempdir/par1.fastq.gz"; $par2name="$tempdir/par2.fastq.gz"; }
		else { $par1name="$tempdir/par1.fastq"; $par2name="$tempdir/par2.fastq"; }
		if($ident{$thisfile} eq "pair1") { $cat1.="$datapath/raw_fastq/$thisfile "; } else { $cat2.="$datapath/raw_fastq/$thisfile "; }
		}
	print "Now merging files\n";
	my $command="$cat1 > $par1name";
	print "$command\n";
	system($command);
	if($cat2) {		#-- Support for single reads
		$command="$cat2 > $par2name";
		print "$command\n";
		system($command);
		}
        my $assemblyname;

	#-- Run the assembly
	#-- For megahit

	if($assembler=~/megahit/i) { 
		system("rm -r $datapath/megahit"); 
		$assemblyname="$datapath/megahit/$thissample.final.contigs.fa";
		if(-e $par2name) { $command="$megahit_soft $assembler_options -1 $par1name -2 $par2name --k-list 29,39,59,79,99,119,141 -t $numthreads -o $datapath/megahit"; }
		else { $command="$megahit_soft $assembler_options -r $par1name --k-list 29,39,59,79,99,119,141 -t $numthreads -o $datapath/megahit"; }	#-- Support for single reads
		print "Running Megahit for $thissample: $command\n";
		system $command;
		system("mv $datapath/megahit/final.contigs.fa $assemblyname");
	}

	#-- For spades

	if($assembler=~/spades/i) { 
		system("rm -r $datapath/spades"); 
		$assemblyname="$datapath/spades/$thissample.contigs.fasta";
		if(-e $par2name) { $command="$spades_soft $assembler_options --meta --pe1-1 $par1name --pe1-2 $par2name -m 400 -t $numthreads -o $datapath/spades"; }
		else { $command="$spades_soft $assembler_options --meta --s1 $par1name -m 400 -t $numthreads -o $datapath/spades"; } #-- Support for single reads
		print "Running Spades for $thissample: $command\n";
		system $command;
		system("mv $datapath/spades/contigs.fasta $assemblyname");
	}
 
       #-- For canu

        if($assembler=~/canu/i) {
                system("rm -r $datapath/canu");
                $assemblyname="$datapath/spades/$thissample.contigs.fasta";
		$command="$canu_soft $assembler_options -p $project -d $datapath/canu genomeSize=5m corOutCoverage=10000 corMhapSensitivity=high corMinCoverage=0 redMemory=32 oeaMemory=32 batMemory=32 mhapThreads=$numthreads mmapThreads=$numthreads ovlThreads=$numthreads ovbThreads=$numthreads ovsThreads=$numthreads corThreads=$numthreads oeaThreads=$numthreads redThreads=$numthreads batThreads=$numthreads gfaThreads=$numthreads merylThreads=$numthreads -nanopore-raw  $datapath/raw_fastq/*fastq";
                print "Running canu for $thissample: $command\n";
                system $command;
                system("mv $datapath/canu/$project.contigs.fasta $assemblyname");
        }




	#-- Run prinseq_lite for removing short contigs

	$contigsfna="$resultpath/01.$project.$thissample.fasta";	#-- Contig file from assembly
	$contigslen="$resultpath/01.$project.$thissample.lon";
	$command="$prinseq_soft -fasta $assemblyname -min_len $mincontiglen -out_good $resultpath/prinseq; mv $resultpath/prinseq.fasta $contigsfna.prov";
	print "Running prinseq: $command\n";
	system $command;

	#-- Now we need to rename the contigs for minimus2, otherwise there will be contigs with same names in different assemblies

	print "Renaming contigs\n"; 
	open(outfile1,">$contigsfna") || die;
	open(infile2,"$contigsfna.prov") || die;
	while(<infile2>) {
		chomp;
		if($_=~/^\>([^ ]+)/) { 
			my $tname=$1; 
			$_=~s/$tname/$tname\_$thissample/; 
		}
	print outfile1 "$_\n";
	}
	close infile2;
	close outfile1;
	system("rm $contigsfna.prov");

	#-- Run prinseq_lite for statistics

	$command="$prinseq_soft -fasta $contigsfna -stats_len -stats_info -stats_assembly > $resultpath/01.$project.$thissample.stats";
	system $command;
	

	#-- Counts length of the contigs (we will need it later)

	print "Counting lengths\n";
	my($seq,$thisname,$contigname);
	open(outfile2,">$contigslen") || die;
	print outfile2 "#-- Created by $0, ",scalar localtime,"\n";
	open(infile3,$contigsfna) || die;
	while(<infile3>) {
		chomp;
		next if !$_;
		if($_=~/^\>([^ ]+)/) {
			$thisname=$1;
			if($contigname) {
				my $len=length $seq;
				print outfile2 "$contigname\t$len\n"; 
			}
			$seq="";
			$contigname=$thisname;
		}
		else { $seq.=$_; }
	}
close infile3;
if($contigname) { my $len=length $seq; print outfile2 "$contigname\t$len\n"; }
close outfile2;

print "Contigs for sample $thissample stored in $contigsfna\n";

}                              #-- End of current sample

# system("rm $tempdir/par1.fastq.gz; rm $tempdir/par2.fastq.gz");

#!/usr/bin/perl

#-- Part of squeezeM distribution. 01/05/2018 Original version, (c) Javier Tamames, CNB-CSIC
#-- Calculates coverage/RPKM for genes/contigs by mapping back reads to the contigs and count how many fall in each gene/contig
#-- Uses bowtie2 for mapping, and bedtools for counting. 
#-- WARNING! Bedtools version must be <0.24!

$|=1;

use strict;
use Cwd;

my $pwd=cwd();
my $project=$ARGV[0];

do "$project/squeezeM_conf.pl";

	#-- Configuration variables from conf file

our($datapath,$bowtieref,$bowtie2_build_soft,$contigsfna,$mappingfile,$resultpath,$rpkmfile,$contigcov,$coveragefile,$bowtie2_x_soft,$gff_file,$tempdir,$numthreads,$scriptdir,$bedtools_soft);

my $keepsam=1;  #-- Set to one, it keeps SAM files. Set to zero, it deletes them when no longer needed

my $fastqdir="$datapath/raw_fastq";
my $samdir="$datapath/sam";

if(-d $samdir) {} else { system("mkdir $samdir"); }

	#-- Creates Bowtie2 reference for mapping (index the contigs)

if(-e "$bowtieref.1.bt2") {} 
else { 
	my $bowtie_command="$bowtie2_build_soft --quiet $contigsfna $bowtieref";
	system($bowtie_command);
	}
 
	#-- Read the sample's file names

my %allsamples;
open(infile1,$mappingfile) || die "Cannot find mappingfile $mappingfile\n";
print "Reading mapping file from $mappingfile\n";
while(<infile1>) {
	chomp;
	next if !$_;
	my @t=split(/\t/,$_);
	if($t[2] eq "pair1") { $allsamples{$t[0]}{"$fastqdir/$t[1]"}=1; } else { $allsamples{$t[0]}{"$fastqdir/$t[1]"}=2; }
	}
close infile1;

	#-- Prepare output files

my @f=keys %allsamples;
my $numsamples=$#f+1;
print "Metagenomes found: $numsamples\n";
if(-e "$resultpath/09.$project.rpkm") { system("rm $resultpath/09.$project.rpkm"); }
if(-e $rpkmfile) { system("rm $rpkmfile"); }
if(-e $contigcov) { system("rm $contigcov"); }
open(outfile1,">$resultpath/09.$project.mappingstat") || die;	#-- File containing mapping statistics
print outfile1 "#-- Created by $0, ",scalar localtime,"\n";
print outfile1 "# Sample\tTotal reads\tMapped reads\tMapping perc\n";

	#-- Now we start mapping the reads of each sample against the reference

foreach my $thissample(keys %allsamples) {
	my($formatseq,$command,$outsam,$formatoption);
	my $nums++;
	my (@pair1,@pair2)=();
	print "Working with $nums: $thissample\n";
	foreach my $ifile(sort keys %{ $allsamples{$thissample} }) {
		if(!$formatseq) {
			if($ifile=~/fasta/) { $formatseq="fasta"; }
			else { $formatseq="fastq"; }
		}
		
	#-- Get reads from samples
		
	if($allsamples{$thissample}{$ifile}==1) { push(@pair1,$ifile); } else { push(@pair2,$ifile); }
	}

	if($#pair1==0) { $command="cp $pair1[0] $tempdir/$project.$thissample.current_1.$formatseq.gz; cp $pair2[0] $tempdir/$project.$thissample.current_2.$formatseq.gz;"; }
	else { 
		my $a1=join(" ",@pair1);					
		my $a2=join(" ",@pair2);	
		$command="cat $a1 > $tempdir/$project.$thissample.current_1.$formatseq.gz; cat $a2 > $tempdir/$project.$thissample.current_2.$formatseq.gz;";	
		}
	print "  Getting raw reads\n";
	print "$command\n";
	system $command;
	
	#-- Now we start mapping reads against contigs
	
	print "  Aligning with Bowtie\n";
	if($keepsam) { $outsam="$samdir/$project.$thissample.sam"; } else { $outsam="$samdir/$project.$thissample.current.sam"; }
	if($formatseq eq "fasta") { $formatoption="-f"; }
	$command="$bowtie2_x_soft -x $bowtieref $formatoption -1 $tempdir/$project.$thissample.current_1.$formatseq.gz -2 $tempdir/$project.$thissample.current_2.$formatseq.gz --quiet -p $numthreads -S $outsam";
	print "$command\n";
	system $command;
	
	#-- And then we call bedtools for counting
	
	# htseq();
	bedtools($thissample,$outsam);
	contigcov($thissample,$outsam);
}
close outfile1;
system("rm $samdir/current.sam");   


#----------------- htseq counting (deprecated)

#sub htseq {
#	print "  Counting with HTSeq\n";
#	my $command="htseq-count -m intersection-nonempty -s no -t CDS -i \"ID\" $outsam $gff_file > $project.$thissample.current.htseq";
#	system $command;
#	print "  Calculating RPKM from HTseq\n";
#	$command="perl $scriptdir/rpkm.pl $project.$thissample.current.htseq $gff_file $thissample >> $resultpath/06.$project.rpkm";
#	system $command;
#}

#----------------- bedtools counting 

sub bedtools {
	print "  Counting with Bedtools\n";
	my($thissample,$outsam)=@_;

	#-- Creating reference for bedtools from the gff file
	#-- Reference has the format: <contig_id> <gen init pos> <gen end pos> <gen ID>

	open(infile2,$gff_file) || die "Cannot find gff file $gff_file\n";  
	# print "Reading gff file from $gff_file\n";
	my $bedreference=$gff_file;
	$bedreference=~s/gff/refbed/;
	print "    Generating reference: $bedreference\n";
	
	open(outfile2,">$bedreference") || die;
	while(<infile2>) {
		my $gid;
		chomp;
		next if(!$_ || ($_=~/^\#/));
		if($_=~/ID\=([^;]+)\;/) { $gid=$1; }	#-- Orf's ID
		my @k=split(/\t/,$_);
		print outfile2 "$k[0]\t$k[3]\t$k[4]\t$gid\n";		# <contig_id> <gen init pos> <gen end pos> <gen ID>
		}
	close infile2;
	close outfile2;

	#-- Creating bedfile from the sam file. It has the format <read id> <init pos match> <end pos match>

	my $bedfile="$tempdir/$project.$thissample.current.bed";
	print "    Generating Bed file: $bedfile\n";
	open(outfile3,">$bedfile") || die;
	open(infile3,$outsam) || die;

	#-- Reading sam file

	while(<infile3>) {
		next if($_=~/^\@/);
		my @k=split(/\t/,$_);
		next if($k[2]=~/\*/);
		my $cigar=$k[5];                       
		my $end=$k[3];

		#-- Calculation of the length match end using CIGAR string

		while($cigar=~/^(\d+)([IDM])/) {
			my $mod=$1;
			my $type=$2;
			if($type=~/M|D/) { $end+=$mod; }	#-- Update end position according to the match found
			elsif($type=~/I/) { $end-=$mod; }
			$cigar=~s/^(\d+)([IDM])//g;
			}
		print outfile3 "$k[2]\t$k[3]\t$end\n";		#-- <read id> <init pos match> <end pos match>
		}
	close infile3;
	close outfile3;

	#-- Call bedtools for counting reads
	
	my $command="$bedtools_soft coverage -a $bedfile -b $bedreference > $tempdir/$project.$thissample.current.bedcount";
	print "    Counting reads: $command\n";
	system $command;	

	#-- Call bedtools for counting reads

	$command="$bedtools_soft coverage -a $bedfile -b $bedreference -d > $tempdir/$project.$thissample.currentperbase.bedcount";
	print "    Counting bases: $command\n";
	system $command;
	
	#-- Run RPKM calculation (rpkm.pl)
	
	print "  Calculating RPKM from Bedtools\n";
	$command="perl $scriptdir/rpkm.pl $tempdir/$project.$thissample.current.bedcount $gff_file $thissample >> $rpkmfile";
	system $command;

	#-- Run coverage calculation (coverage.pl)	

	print "  Calculating Coverage from Bedtools\n";
	$command="perl $scriptdir/coverage.pl $tempdir/$project.$thissample.currentperbase.bedcount $gff_file $thissample >> $coveragefile";
	system $command;
	
	#-- Remove files
	
	print "  Removing files\n";
	#system("rm $tempdir/$project.$thissample.current_1.fastq.gz");
	#system("rm $tempdir/$project.$thissample.current_2.fastq.gz");
	#system("rm $tempdir/$project.$thissample.current.bedcount");
	#system("rm $tempdir/$project.$thissample.currentperbase.bedcount"); 
	#system("rm $tempdir/$project.$thissample.current.bed"); 
}


#----------------- Contig coverage


sub contigcov {
	print "  Calculating contig coverage\n";
	my($thissample,$outsam)=@_;
	my(%lencontig,%readcount)=();
	my($mappedreads,$totalreadcount)=0;
	open(outfile4,">>$contigcov") || die;

	#-- Count length of contigs and bases mapped from the sam file

	open(infile4,$outsam);
	while(<infile4>) {
		chomp;
		my @t=split(/\t/,$_);

		#-- Use the headers to extract contig length

		if($_=~/^\@/) {
		$t[1]=~s/SN\://;
		$t[2]=~s/LN\://;
		$lencontig{$t[1]}=$t[2];
		}
	
		#-- And the mapped reads to sum base coverage

		else {
			if($t[2]!~/\*/) { 			#-- If the read mapped, accum reads and bases
				$readcount{$t[2]}{reads}++;
				$readcount{$t[2]}{lon}+=length $t[9];
				$mappedreads++;
			}       
			$totalreadcount++;
		} 
	}
	close infile4;
	
	my $mapperc=($mappedreads/$totalreadcount)*100;
	printf outfile1 "$thissample\t$totalreadcount\t$mappedreads\t%.2f\n",$mapperc;		#-- Mapping statistics

	#-- Output RPKM/coverage values

	print outfile4 "#-- Created by $0, ",scalar localtime,"\n";
	print outfile4 "# Contig ID\tAv Coverage\tRPKM\tContig length\tRaw reads\tRaw bases\tSample\n";
	foreach my $rc(sort keys %readcount) { 
		my $longt=$lencontig{$rc};
		next if(!$longt);
		my $coverage=$readcount{$rc}{lon}/$longt;
		my $rpkm=($readcount{$rc}{reads}*1000000000)/($longt*$totalreadcount);
		if(!$rpkm) { print outfile4 "$rc\t0\t0\t$longt\t$readcount{$rc}{reads}\t$readcount{$rc}{lon}\t$thissample\n"; } 
		else { printf outfile4 "$rc\t%.3f\t%.3f\t$longt\t$readcount{$rc}{reads}\t$readcount{$rc}{lon}\t$thissample\n",$coverage,$rpkm; }
		}
	close outfile4;	
}


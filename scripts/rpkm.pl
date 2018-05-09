#!/usr/bin/perl

#-- Part of squeezeM distribution. 01/05/2018 Original version, (c) Javier Tamames, CNB-CSIC
#-- Calculates RPKM for genes by counting reads mapped to each feature

use strict;

my $bedfile=$ARGV[0];		# htseq|bedtools file
my $gff_file=$ARGV[1];		# gff file
my $sample=$ARGV[2];		# Sample ID

my(%long,%ids);

#-- Read gff file to get gen positions

open(infile1,$gff_file) || die;
while(<infile1>) {
	chomp;
	next if(!$_ || ($_=~/\#/));
	my @k=split(/\t/,$_);
	my($id,$newid);
	if($_=~/ID\=([^;]+)/) { 
		$id=$1;
		my @listh=split(/\_/,$id);
		# ($base,$contigid,$num)=split(/\_/,$id);
		$newid="$k[0]\_$listh[$#listh]"; 
		}
	my $length=$k[4]-$k[3]+1;
	$long{$id}=$length;
	$ids{$id}=$newid;
            }
close infile1;

#-- Read mapping file (bedcount file) to count total number of reads 

open(infile2,$bedfile) || die "Cannot open bedtools file $bedfile\n";
my $totcount;
while(<infile2>) {
	chomp;
	next if !$_;
	my @fd=split(/\t/,$_);
	my($gn,$gcount);
	if($bedfile=~/htseq/) { $gn=$fd[0]; $gcount=$fd[1]; } 	#-- HTseq
	else { $gn=$fd[3]; $gcount=$fd[4]; } 			#-- Bedtools (Warning! v<0.24)
	$totcount+=$gcount;
	}
close infile2;

#-- Read mapping file (bedcount file) to count reads to features

print "# Created by $0 from $bedfile, ",scalar localtime,"\n";
print "# Gen	RPKM	Raw counts	Sample	Gen length\n";
open(infile3,$bedfile) || die;
while(<infile3>) {
	chomp;
	next if !$_;
	my @fd=split(/\t/,$_);
	my($gn,$gcount);
	if($bedfile=~/htseq/) { $gn=$fd[0]; $gcount=$fd[1]; } 	#-- HTseq
	else { $gn=$fd[3]; $gcount=$fd[4]; }                    #-- Bedtools  (Warning! v<0.24)
	my $longt=$long{$gn};
	my $oid=$ids{$gn};
	next if(!$longt);
	my $rpkm=(($gcount*1000000000)/($longt*$totcount));
	if(!$rpkm) { print "$oid\t0\t$gcount\t$sample\t$longt\n"; } else { printf "$oid\t%.3f\t$gcount\t$sample\t$longt\n",$rpkm; }
	}
close infile3;

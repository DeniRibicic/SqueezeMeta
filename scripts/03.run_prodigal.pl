#!/usr/bin/perl

#-- Part of SqueezeMeta distribution. 01/05/2018 Original version, (c) Javier Tamames, CNB-CSIC
#-- Runs Prodigal software for predicting ORFs
#-- 30/01/19 Includes changing of naming schema to accomodate blastx predictions

use strict;
use warnings;
use Cwd;
use lib ".";

my $pwd=cwd();

my $project=$ARGV[0];
$project=~s/\/$//; 
if(-s "$project/SqueezeMeta_conf.pl" <= 1) { die "Can't find SqueezeMeta_conf.pl in $project. Is the project path ok?"; }
do "$project/SqueezeMeta_conf.pl";

our($resultpath,$tempdir,$interdir,$aafile,$ntfile,$gff_file,$prodigal_soft);

#-- Runs prodigal and cat the gff file with the RNA's one coming from barrnap (previous step)

my $tempgff="$tempdir/02.$project.cds.gff.temp";
my $tempgff2="$tempdir/02.$project.cds.gff";
my $tempaa="$tempdir/02.$project.aa.temp";
my $tempnt="$tempdir/02.$project.nt.temp";

my $maskedcontigs="$interdir/02.$project.maskedrna.fasta";
my $command="$prodigal_soft -q -m -p meta -i $maskedcontigs -a $aafile -d $ntfile -f gff -o $tempgff";
print "Running prodigal\n";
my $ecode = system $command;
if($ecode!=0) { die "Error running command:    $command"; }

#-- Reanaming genes for accomodating better upcoming blastx predictions

open(outfile1,">$tempaa") || die;
open(infile1,$aafile) || die "Cannot open $aafile\n";
while(<infile1>) {
	if($_=~/^\>/) { 
		$_=~s/^\>//;
		my @w=split(/\s\#\s/,$_);
		my $nwname=$w[0];
		$nwname=~s/\_\d+$/\_$w[1]-$w[2]/;
		splice(@w,0,1,$nwname);
		print outfile1 ">",join(" # ",@w);
		}
	else { print outfile1 $_; }
	}
close infile1;
close outfile1;
system("mv $tempaa $aafile");

	
open(outfile2,">$tempnt") || die;
open(infile2,$ntfile) || die;
while(<infile2>) {
	if($_=~/^\>/) { 
		$_=~s/^\>//;
		my @w=split(/\s\#\s/,$_);
		my $nwname=$w[0];
		$nwname=~s/\_\d+$/\_$w[1]-$w[2]/;
		splice(@w,0,1,$nwname);
		print outfile2 ">",join(" # ",@w);
		}
	else { print outfile2 $_; }
	}
close infile2;
close outfile2;	
system("mv $tempnt $ntfile");

open(outfile3,">$tempgff2") || die;
open(infile3,$tempgff) || die "Cannot open $tempgff\n";
while(<infile3>) {
	chomp;
	if($_!~/^\#/) { 
		my @w=split(/\t/,$_);
		my $idp="$w[0]\_$w[3]-$w[4]"; 
		$w[8]=~s/ID\=\d+\_\d+/ID\=$idp/;
		print outfile3 join("\t",@w),"\n";
		}
	else { print outfile3 "$_\n"; }
	}
close infile3;
close outfile3;	
	
system("cat $tempgff2 $tempdir/02.$project.rna.gff > $gff_file");


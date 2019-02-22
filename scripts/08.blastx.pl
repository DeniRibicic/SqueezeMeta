#!/usr/bin/perl

#-- Part of SqueezeMeta distribution. 28/01/2019 for version 0.5.0, (c) Javier Tamames, CNB-CSIC
#-- Runs Diamond blastx for unmapped parts of the contigs, annotates tax and functions for the hits, and merge them with prodigal ORFs
#-- Uses several external scripts:
#	blastxcollapse.pl for collapsing blastx hits
#	mergehits.pl for merging frameshifted ORFs
#	lca_collapse.pl, remvamped version of lca.pl for working with the collapsed format
#	good old fun3assign.pl for annotating COGs/KEGGs


$|=1;

use strict;
use Cwd;
use lib ".";

my $pwd=cwd();
my $project=$ARGV[0];
$project=~s/\/$//; 
if(!$project) { die "Please specify a project name\n"; }

do "$project/SqueezeMeta_conf.pl";

	#-- Configuration variables from conf file

our($datapath,$contigsfna,$mergedfile,$gff_file,$ntfile,$resultpath,$nr_db,$gff_file,$blocksize,$evalue,$rnafile,$tempdir,$gff_file_blastx,$fna_blastx,$fun3tax_blastx,$fun3kegg_blastx,$fun3cog_blastx,$installpath,$numthreads,$scriptdir,$fun3tax,$fun3cog,$fun3kegg,$fun3pfam,$diamond_soft,$nocog,$nokegg,$nopfam,$cog_db,$kegg_db,$miniden);


my($header,$keggid,$cogid,$taxid,$pfamid,$maskedfile,$blastxout,$collapsed,$collapsedmerged,$ntmerged,$cogfun,$keggfun);
my(%genpos,%skip,%allorfs,%annotations,%incontig);

my $idenfilters=1;	#-- Set to 1, CONSIDERS identity filters for taxa. Set to 0, it does not
my $nomasked=100;	#-- Minimum unmasked length for a contig to be considered in blastx

masking();
run_blastx();
collapse();
merge();
getseqs();
lca();
functions();
remaketaxtables();
remakefuntables();
remakegff();

	#-- Moving old files to tempdir
	
#system("mv $resultpath/06.$project.fun3.tax.wranks $tempdir/06.$project.fun3.tax.genepred.wranks;");
#if(!$nocog) { system("mv $resultpath/07.$project.fun3.cog $tempdir/07.$project.fun3.cog.genepred;"); }
#if(!$nokegg) { system("mv $resultpath/07.$project.fun3.kegg $tempdir/07.$project.fun3.kegg.genepred;"); }
#system("mv $resultpath/03.$project.gff $tempdir/03.$project.genepred.gff;");



sub masking() {
	print "Getting segments for masking\n";
	open(infile1,"$resultpath/06.$project.fun3.tax.wranks") || die "Cannot open wranks file in $resultpath/06.$project.fun3.tax.wranks\n";
	while(<infile1>) {
		my @t=split(/\t/,$_);
		$annotations{$t[0]}{tax}=$t[1];
		}
	close infile1;
	open(infile1,$rnafile) || die "Cannot open rna file in $rnafile\n";
	while(<infile1>) {
		my @t=split(/\t/,$_);
		$t[0]=~s/^\>//;
		$annotations{$t[0]}{rna}=$t[1];
		}
	close infile1;
	
	if(!$nocog) { 
		open(infile2,$fun3cog) || die "Cannot open cog file in $fun3cog\n";
		while(<infile2>) {
			my @t=split(/\t/,$_);
			$annotations{$t[0]}{cog}=$t[1];
			}
		close infile2;
		}
	if(!$nokegg) { 
		open(infile2,$fun3kegg) || die "Cannot open kegg file in $fun3kegg\n";
		while(<infile2>) {
			my @t=split(/\t/,$_);
			$annotations{$t[0]}{kegg}=$t[1];
			}
		close infile2;
		}
	if(!$nopfam) { 
		open(infile2,$fun3pfam) || die "Cannot open pfam file in $fun3pfam\n";
		while(<infile2>) {
			my @t=split(/\t/,$_);
			$annotations{$t[0]}{pfam}=$t[1];
			}
		close infile2;
		}
	
		
	foreach my $tgene(keys %annotations) {		
		my @f=split(/\t/,$tgene);
		my @gpos=split(/\_/,$f[0]);
		my $posn=pop @gpos;
		my $contname=join("_",@gpos);
		$genpos{$contname}{$posn}=$f[0];
	
		#-- If there is taxonomic and/or functional annotation, we consider the gene as correctly predicted
		if(($annotations{$tgene}{tax}=~/superkingdom/) || ($annotations{$tgene}{cog}) ||  ($annotations{$tgene}{kegg}) || ($annotations{$tgene}{pfam})) {
			$skip{$f[0]}=1;
			# print "Skip $f[0]\n";
			}
		}	


	print "Masking contigs\n";
	$maskedfile=$contigsfna;
	$maskedfile="$tempdir/08.$project.masked.fna";
	# if (-e $maskedfile) { die "File $maskedfile already exists\n"; }
	open(outfile,">$maskedfile");
	open(infile3,$contigsfna) || die;
	my($seq,$current)="";
	while(<infile3>) {
		chomp;
			if($_=~/^\>([^ ]+)/) { 
				my $contigname=$1; 
				my $numn=0;
				if($current) { 

					#-- Masking with 'N's

					foreach my $gene(sort keys %{ $genpos{$current} }) {
						my($init,$end)=split(/\-/,$gene);
						my $longr=($end-$init)+1;
						my $replace=('N' x $longr);
						$numn+=$longr;
						# print "$current $gene\n$seq\n$init\n$longr\n$replace\n";
						substr($seq,$init-1,$longr)=$replace;
						}
				}
				if($current && ((length $seq)-$numn>=$nomasked)) { print outfile ">$current\n$seq\n"; }	
				$seq="";
				$current=$contigname;     
			}
			else { $seq.=$_; }
		}
	close infile3;
	close outfile;
	print "Output in $maskedfile\n";
	}


sub run_blastx {

	#-- Run Diamond search

	print "Running Diamond BlastX (This can take a while, please be patient)\n";
	$blastxout="$resultpath/08.$project.nr.blastx";
	my $blastx_command="$diamond_soft blastx -q $maskedfile -p $numthreads -d $nr_db -f tab -F 15 -k 0 --quiet -b $blocksize -e $evalue -o $blastxout";
	# print "$blastx_command\n";
	# system $blastx_command;
	}

sub collapse {

	#-- Collapse hits using blastxcollapse.pl

	print "Collapsing hits with blastxcollapse.pl\n";
	$collapsed="$tempdir/08.$project.nr.blastx.collapsed.m8";
	my $collapse_command="$scriptdir/blastxcollapse.pl -n -s -f -m 50 -l 70 $blastxout > $collapsed";
	system $collapse_command;
	}
	
sub merge {

	#-- Merge frameshifts

	$collapsedmerged=$collapsed;
	$collapsedmerged=~s/\.m8/\.merged\.m8/;
	my $merge_command="$scriptdir/mergehits.pl $collapsed > $collapsedmerged";
	print "Merging splitted hits with mergehits.pl\n";
	system $merge_command;
	}

sub getseqs {

	#-- Get new nt sequences

	$collapsedmerged="$tempdir/08.$project.nr.blastx.collapsed.merged.m8";
	print "Getting nt sequences\n";
	my %orfstoget;
	open(infile4,$collapsedmerged) || die;
	while(<infile4>) {
		chomp;
		next if(!$_ || ($_=~/^\#/));
		my @t=split(/\t/,$_);
		my @w=split(/\_/,$t[0]);
		my $posn=pop @w;
		my $contname=join("_",@w);
		$orfstoget{$contname}{$posn}=1;
		# print "$contname*$posn*\n";
		}
	close infile4;

	$ntmerged=$fna_blastx;
	my($currcontig,$newcontig,$contigseq);
	open(outfile2,">$ntmerged") || die;
	open(infile5,$contigsfna) || die;
	while(<infile5>) {
		chomp;
		next if(!$_ || ($_=~/^\#/));
		if($_=~/^\>([^ ]+)/) { 
			$newcontig=$1; 
			if($currcontig) {
				foreach my $gorf(keys %{ $orfstoget{$currcontig} }) {
					my($pinit,$pend)=split(/\-/,$gorf);
					my $tlen=$pend-$pinit+1;
					my $mseq=substr($contigseq,$pinit,$tlen);
					print outfile2 ">$currcontig\_$gorf\n$mseq\n";
					}
				}
			$currcontig=$newcontig;
			$contigseq="";
			}
		else { $contigseq.=$_; }
	}	
	close infile5;
	foreach my $gorf(keys %{ $orfstoget{$currcontig} }) {
		my($pinit,$pend)=split(/\-/,$gorf);
		my $tlen=length($pend-$pinit+1);
		my $mseq=substr($contigseq,$pinit,$tlen);
		print outfile2 ">$currcontig\_$gorf\n$mseq\n";
		}
	close outfile2;	
	print "Sequences stored in $ntmerged\n";				
	}

sub lca {

	#-- Assign with lca_collapsed

	print "Now running lca_collapse.pl\n";
	system("perl $scriptdir/lca_collapse.pl $project $collapsedmerged");
	}

sub functions {

	#-- COG database

	if(!$nocog) {
		$cogfun="$tempdir/08.$project.fun3.blastx.cog.m8";
		my $command="$diamond_soft blastx -q $ntmerged -p $numthreads -d $cog_db -e $evalue --id $miniden -b 8 -f 6 qseqid qlen sseqid slen pident length evalue bitscore qstart qend sstart send -o $cogfun";
		print "Running Diamond blastx for COGS: $command\n";
		my $ecode = system $command;
		if($ecode!=0) { die "Error running command:    $command"; }
		}

	#-- KEGG database

	if(!$nokegg) {
		$keggfun="$tempdir/08.$project.fun3.blastx.kegg.m8";
		my $command="$diamond_soft blastx -q $ntmerged -p $numthreads -d $kegg_db -e $evalue --id $miniden -b 8 -f 6 qseqid qlen sseqid slen pident length evalue bitscore qstart qend sstart send -o $keggfun";
		print "Running Diamond blastx for KEGG: $command\n";
		my $ecode = system $command;
		if($ecode!=0) { die "Error running command:    $command"; }
		}
	print "Assigning with fun3\n";
	system("perl $scriptdir/07.fun3assign.pl $project blastx");
	}

sub remaketaxtables {
	print "Merging tax tables\n";
	my $wranktable=$fun3tax.".wranks";
	my $blastxtable;
	my $newtable=$fun3tax_blastx.".wranks";
	my(%intable,%methods);
	if($idenfilters) { $blastxtable="$resultpath/08.$project.fun3.blastx.tax.wranks"; }
	else { $blastxtable="$resultpath/08.$project.fun3.blastx.tax_nofilter.wranks"; }
	open(infile6,$wranktable) || die "Cannot open nr wrank $wranktable\n";
	while(<infile6>) {
		chomp;
		next if(!$_ || ($_=~/^\#/));
		my @r=split(/\t/,$_);
		next if(!$skip{$r[0]});
		$intable{$r[0]}=$r[1];
		$methods{$r[0]}="prodigal";
		my @sf=split(/\_/,$r[0]);
		my $ipos=pop @sf;
		my($poinit,$poend)=split(/\-/,$ipos);
		my $tcontig=join("_",@sf);
		$incontig{$tcontig}{$poinit}=$poend;
		}
	close infile6;
	open(infile7,$blastxtable) || die "Cannot open blastx wrank $blastxtable\n";
	while(<infile7>) {
		chomp;
		next if(!$_ || ($_=~/^\#/));
		my @r=split(/\t/,$_);
		next if(!$r[0]);
		$intable{$r[0]}=$r[1];
		$methods{$r[0]}="blastx";
		my @sf=split(/\_/,$r[0]);
		my $ipos=pop @sf;
		my($poinit,$poend)=split(/\-/,$ipos);
		my $tcontig=join("_",@sf);
		$incontig{$tcontig}{$poinit}=$poend;
		}
	close infile7;
	
			#-- Sorting first by contig ID, then by position in contig

	open(outfile3,">$newtable") || die "Cannot open output in $newtable\n";
	print outfile3 "# Created by $0 merging $wranktable and $blastxtable,",scalar localtime,"\n";
	my (@listorfs,@sortedorfs);
	foreach my $orf(keys %intable) {
		my @y=split(/\_|\-/,$orf);
		push(@listorfs,{'orf',=>$orf,'contig'=>$y[1],'posinit'=>$y[2]});
		}
	@sortedorfs=sort {
		$a->{'contig'} <=> $b->{'contig'} ||
		$a->{'posinit'} <=> $b->{'posinit'}
		} @listorfs;

	foreach my $orfm(@sortedorfs) { 
		my $orf=$orfm->{'orf'};
		# print outfile3 "$orf\t$intable{$orf}\t$methods{$orf}\n";
		print outfile3 "$orf\t$intable{$orf}\n";
		$allorfs{$orf}=1;
		}
	close outfile3;	
	}
		
sub remakefuntables {
	if(!$nocog) {
		my(%intable,%methods);
		print "Merging COG tables\n";
		my $oldcogtable="$resultpath/07.$project.fun3.cog";
		my $blastxcogtable="$tempdir/08.$project.fun3.blastx.cog";
		my $newcogtable=$fun3cog_blastx;
		open(infile8,$oldcogtable) || die "Cannot open $oldcogtable\n";
			while(<infile8>) {
			chomp;
			next if(!$_ || ($_=~/^\#/));
			my @r=split(/\t/,$_);
			next if(!$skip{$r[0]});
			$intable{$r[0]}="$r[1]\t$r[2]";
			$methods{$r[0]}="prodigal";
			my @sf=split(/\_/,$r[0]);
			my $ipos=pop @sf;
			my($poinit,$poend)=split(/\-/,$ipos);
			my $tcontig=join("_",@sf);
			$incontig{$tcontig}{$poinit}=$poend;
			}
		close infile8;
		open(infile9,$blastxcogtable) || die "Cannot open $blastxcogtable\n";
			while(<infile9>) {
			chomp;
			next if(!$_ || ($_=~/^\#/));
			my @r=split(/\t/,$_);
			next if(!$r[0]);
			$intable{$r[0]}="$r[1]\t$r[2]";
			$methods{$r[0]}="blastx";
			my @sf=split(/\_/,$r[0]);
			my $ipos=pop @sf;
			my($poinit,$poend)=split(/\-/,$ipos);
			my $tcontig=join("_",@sf);
			$incontig{$tcontig}{$poinit}=$poend;
			}
		close infile9;
			#-- Sorting first by contig ID, then by position in contig

		open(outfile4,">$newcogtable") || die "Cannot open output in $newcogtable\n";
		print outfile4 "# Created by $0 merging $oldcogtable and $blastxcogtable,",scalar localtime,"\n";
		print outfile4 "#ORF	BESTHIT	BESTAVER\n";
		my (@listorfs,@sortedorfs);
		foreach my $orf(keys %intable) {
			my @y=split(/\_|\-/,$orf);
			push(@listorfs,{'orf',=>$orf,'contig'=>$y[1],'posinit'=>$y[2]});
			}
		@sortedorfs=sort {
			$a->{'contig'} <=> $b->{'contig'} ||
			$a->{'posinit'} <=> $b->{'posinit'}
			} @listorfs;

		foreach my $orfm(@sortedorfs) { 
			my $orf=$orfm->{'orf'};
			print outfile4 "$orf\t$intable{$orf}\n";
			$allorfs{$orf}=1;
			}
		close outfile4;	
		}
	if(!$nokegg) {
		my(%intable,%methods);
		print "Merging KEGG tables\n";
		my $oldkeggtable="$resultpath/07.$project.fun3.kegg";
		my $blastxkeggtable="$tempdir/08.$project.fun3.blastx.kegg";
		my $newkeggtable=$fun3kegg_blastx;
		open(infile9,$oldkeggtable) || die "Cannot open $oldkeggtable\n";
			while(<infile9>) {
			chomp;
			next if(!$_ || ($_=~/^\#/));
			my @r=split(/\t/,$_);
			next if(!$skip{$r[0]});
			$intable{$r[0]}="$r[1]\t$r[2]";
			$methods{$r[0]}="prodigal";
			my @sf=split(/\_/,$r[0]);
			my $ipos=pop @sf;
			my($poinit,$poend)=split(/\-/,$ipos);
			my $tcontig=join("_",@sf);
			$incontig{$tcontig}{$poinit}=$poend;
			}
		close infile9;
		open(infile10,$blastxkeggtable) || die "Cannot open $blastxkeggtable\n";
			while(<infile10>) {
			chomp;
			next if(!$_ || ($_=~/^\#/));
			my @r=split(/\t/,$_);
			next if(!$r[0]);
			$intable{$r[0]}="$r[1]\t$r[2]";
			$methods{$r[0]}="blastx";
			my @sf=split(/\_/,$r[0]);
			my $ipos=pop @sf;
			my($poinit,$poend)=split(/\-/,$ipos);
			my $tcontig=join("_",@sf);
			$incontig{$tcontig}{$poinit}=$poend;
			}
		close infile10;
			#-- Sorting first by contig ID, then by position in contig

		open(outfile5,">$newkeggtable") || die "Cannot open output in $newkeggtable\n";
		print outfile5 "# Created by $0 merging $oldkeggtable and $blastxkeggtable,",scalar localtime,"\n";
		print outfile5 "#ORF	BESTHIT	BESTAVER\n";
		my (@listorfs,@sortedorfs);
		foreach my $orf(keys %intable) {
			my @y=split(/\_|\-/,$orf);
			push(@listorfs,{'orf',=>$orf,'contig'=>$y[1],'posinit'=>$y[2]});
			}
		@sortedorfs=sort {
			$a->{'contig'} <=> $b->{'contig'} ||
			$a->{'posinit'} <=> $b->{'posinit'}
			} @listorfs;

		foreach my $orfm(@sortedorfs) { 
			my $orf=$orfm->{'orf'};
			print outfile5 "$orf\t$intable{$orf}\n";
			$allorfs{$orf}=1;
			}
		close outfile5;	
		}
	}
	
		
sub remakegff {
	print "Merging GFF tables\n";
	my %gffstore;
	my $gfftable="$resultpath/03.$project.gff";
	my $newtable=$gff_file_blastx;
	open(outfile6,">$newtable") || die "Cannot open output in $newtable\n";
	print outfile6 "# Created by $0, ",scalar localtime,"\n";
	open(infile11,$gfftable) || die "Cannot open $gfftable\n";
	while(<infile11>) {
		chomp;
		next if(!$_ || ($_=~/^\#/));
		my @r=split(/\t/,$_);
		my $orfid;
		if($r[8]=~/ID\=([^;]+)/) { 
			my $oid=$1;
			$gffstore{$oid}=$_; 
			my @sf=split(/\_/,$oid);
			my $ipos=pop @sf;
			my($poinit,$poend)=split(/\-/,$ipos);	#Let's see if this original prodigal CDS overlaps with a new blastx one
			my $tcontig=join("_",@sf);
			my $olap=0;
			foreach my $initpres(sort keys %{ $incontig{$tcontig} }) {
				my $endpres=$incontig{$tcontig}{$initpres};
				if(($initpres>=$poinit) && ($initpres<=$poend))  { $olap=1; last; }	# A blastx hit starts into a prodigal CDS
				if(($endpres>=$poinit) && ($endpres<=$poend)) { $olap=1; last; }	# A blastx hit ends into a prodigal CDS
				}
			if(!$olap) { $allorfs{$oid}=1; }
			}
		}
	close infile11;
	
			#-- Sorting first by contig ID, then by position in contig

	my (@listorfs,@sortedorfs);
	foreach my $orf(keys %allorfs) { 
		my @sf=split(/\_/,$orf);
		my $ipos=pop @sf;
		my $contname=join("_",@sf);
		my($poinit,$poend)=split(/\-/,$ipos);
		push(@listorfs,{'orf',=>$orf,'contig'=>$contname,'posinit'=>$poinit});
		}
	@sortedorfs=sort {
		$a->{'contig'} <=> $b->{'contig'} ||
		$a->{'posinit'} <=> $b->{'posinit'}
		} @listorfs;

	foreach my $orfm(@sortedorfs) { 
		my $orf=$orfm->{'orf'};
		if($gffstore{$orf}) { print outfile6 "$gffstore{$orf}\n"; }
		else {
			my @y=split(/\_|\-/,$orf);
			my @sf=split(/\_/,$orf);
			my $ipos=pop @sf;
			my $contname=join("_",@sf);
			my($poinit,$poend)=split(/\-/,$ipos);
			print outfile6 "$contname\tDiamond Blastx\tCDS\t$poinit\t$poend\t?\t?\t?\tID=$orf;\n";
			}
	
		}
	close outfile3;	
	print "New GFF table created in $newtable\n";
	}

#!/usr/bin/perl

use strict;

use Cwd 'abs_path';
my $databasedir=abs_path($ARGV[0]);

if(!$databasedir) { die "Usage: perl install_nodb.pl <database dir>\n"; }
print("Make sure that $databasedir contains all the database files (nr.dmnd, etc...)\n\n");

###scriptdir patch, Fernando Puente-Sánchez, 07-V-2018
use File::Basename;
our $dbscriptdir = dirname(__FILE__);
our $installpath = abs_path("$dbscriptdir/../..");
our $libpath = "$installpath/lib";
###


system("rm $libpath/classifier.tar.gz");

###Download rdp classifier.
print("Downloading and unpacking RDP classifier...\n");
system("wget -U '' -P $libpath http://wwwuser.cnb.csic.es/~squeezem/classifier.tar.gz; tar -xvzf $libpath/classifier.tar.gz -C $libpath; rm $libpath/classifier.tar.gz");

###Update configuration files to reflect new db path.
print("\nUpdating configuration...\n");


my $checkm_manifest = "{\"dataRoot\": \"$databasedir\", \"remoteManifestURL\": \"https://data.ace.uq.edu.au/public/CheckM_databases/\", \"manifestType\": \"CheckM\", \"localManifestName\": \".dmanifest\", \"remoteManifestName\": \".dmanifest\"}\n";

open(outfile1, ">$installpath/lib/checkm/DATA_CONFIG") || die;
print outfile1 $checkm_manifest;
close outfile1;

open(outfile2,">$installpath/scripts/SqueezeMeta_conf.pl") || die;
open(infile1, "$installpath/scripts/SqueezeMeta_conf_original.pl") || die;
while(<infile1>) {
	if($_=~/^\$databasepath/) { print outfile2 "\$databasepath=\"$databasedir\";\n"; }
	else { print outfile2 $_; }
	}
close infile1;
close outfile2;

print("Done\n");


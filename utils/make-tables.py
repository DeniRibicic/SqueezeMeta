#!/usr/bin/python3

"""
Part of the SqueezeMeta distribution. 25/03/2018 Original version, (c) Fernando Puente-Sánchez, CNB-CSIC.

Generate tabular outputs from SqueezeMeta results.

USAGE: make-tables.py <PROJECT_NAME> <OUTPUT_DIRECTORY>

OPTIONS:
    --ignore_unclassified: Ignore ORFs without assigned functions in TPM calculation

"""

from os.path import abspath, dirname, realpath
from os import mkdir
import argparse

from numpy import array, isnan, seterr
seterr(divide='ignore', invalid='ignore')
from collections import defaultdict

from sys import path
utils_home = abspath(dirname(realpath(__file__)))
path.append('{}/../lib/'.format(utils_home))
from utils import parse_conf_file


TAXRANKS = ('superkingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species')
TAXRANKS_SHORT = ('k', 'p', 'c', 'o', 'f', 'g', 's')

def main(args):
    ### Get result files paths from SqueezeMeta_conf.pl
    perlVars = parse_conf_file(args.project_path)
    nokegg, nocog, nopfam, doublepass = map(int, [perlVars['$nokegg'], perlVars['$nocog'], perlVars['$nopfam'], perlVars['$doublepass']])

    ### Create output dir.
    try:
       mkdir(args.output_dir)
    except OSError as e:
        if e.errno != 17:
            raise

    ### Calculate tables and write results.
    prefix = args.output_dir + '/' + perlVars['$projectname'] + '.'
    
    sampleNames, orfs, kegg, cog, pfam = parse_orf_table(perlVars['$mergedfile'], nokegg, nocog, nopfam, args.ignore_unclassified)

    # Round aggregated functional abundances.
    # We can have non-integer abundances bc of the way we split counts in ORFs with multiple KEGGs.
    # We round the aggregates to the closest integer for convenience.
    kegg['abundances'] = {k: a.round().astype(int) for k,a in kegg['abundances'].items()}
    cog['abundances']  = {k: a.round().astype(int) for k,a in  cog['abundances'].items()}
    pfam['abundances'] = {k: a.round().astype(int) for k,a in pfam['abundances'].items()}

    #write_results(sampleNames, orfs['tpm'], prefix + 'orf.tpm.tsv')
    if not nokegg:
        write_results(sampleNames, kegg['abundances'], prefix + 'KO.abund.tsv')
        write_results(sampleNames, kegg['tpm'], prefix + 'KO.tpm.tsv')
    if not nocog:
        write_results(sampleNames, cog['abundances'], prefix + 'COG.abund.tsv')
        write_results(sampleNames, cog['tpm'], prefix + 'COG.tpm.tsv')
    if not nopfam:
        write_results(sampleNames, pfam['abundances'], prefix + 'PFAM.abund.tsv')
        write_results(sampleNames, pfam['tpm'], prefix + 'PFAM.tpm.tsv')

    fun_prefix = perlVars['$fun3tax_blastx'] if doublepass else perlVars['$fun3tax']
    orf_tax, orf_tax_wranks = parse_tax_table(fun_prefix + '.wranks')
    orf_tax_nofilter, orf_tax_nofilter_wranks = parse_tax_table(fun_prefix + '.noidfilter.wranks')

    # Add ORFs not present in the input tax file.
    unclass_list = ['Unclassified' for rank in TAXRANKS_SHORT]
    unclass_list_wranks = ['{}_Unclassified' for rank in TAXRANKS_SHORT]
    for orf in orfs['abundances']:
        if orf not in orf_tax:
            assert orf not in orf_tax_wranks
            assert orf not in orf_tax_nofilter
            assert orf not in orf_tax_nofilter_wranks
            orf_tax[orf] = unclass_list
            orf_tax_wranks[orf] = unclass_list_wranks
            orf_tax_nofilter[orf] = unclass_list
            orf_tax_nofilter_wranks[orf] = unclass_list_wranks

    
    orf_tax_prokfilter, orf_tax_prokfilter_wranks = {}, {}

    for orf in orf_tax:
        tax = orf_tax[orf]
        tax_nofilter = orf_tax_nofilter[orf]
        if 'Bacteria' in (tax[0], tax_nofilter[0]) or 'Archaea' in (tax[0], tax_nofilter[0]): # We check both taxonomies.
            orf_tax_prokfilter       [orf] = tax
            orf_tax_prokfilter_wranks[orf] = orf_tax_wranks[orf]
        else:
            orf_tax_prokfilter       [orf] = tax_nofilter
            orf_tax_prokfilter_wranks[orf] = orf_tax_nofilter_wranks[orf]
            

    #write_results(TAXRANKS, orf_tax, prefix + 'orf.tax.allfilter.tsv')
    #write_results(TAXRANKS, orf_tax_nofilter, prefix + 'orf.tax.nofilter.tsv')
    #write_results(TAXRANKS, orf_tax_prokfilter, prefix + 'orf.tax.prokfilter.tsv')

    contig_abunds, contig_tax, contig_tax_wranks = parse_contig_table(perlVars['$contigtable'])
    #write_results(TAXRANKS, contig_tax, prefix + 'contig.tax.tsv')

    for idx, rank in enumerate(TAXRANKS):
        tax_abunds_orfs = aggregate_tax_abunds(orfs['abundances'], orf_tax_prokfilter, idx)
        write_results(sampleNames, tax_abunds_orfs, prefix + '{}.prokfilter.abund.orfs.tsv'.format(rank))

        tax_abunds_contigs = aggregate_tax_abunds(contig_abunds, contig_tax_wranks, idx)
        write_results(sampleNames, tax_abunds_contigs, prefix + '{}.allfilter.abund.tsv'.format(rank))
        write_results(sampleNames, normalize_abunds(tax_abunds_contigs, 100), prefix + '{}.allfilter.percent.tsv'.format(rank))



def parse_orf_table(orf_table, nokegg, nocog, nopfam, ignore_unclassified_fun, orfSet=None):

    orfs = {res: {} for res in ('abundances', 'copies', 'lengths')} # I know I'm being inconsistent with camelcase and underscores... ¯\_(ツ)_/¯
    kegg = {res: defaultdict(int) for res in ('abundances', 'copies', 'lengths')}
    cog  = {res: defaultdict(int) for res in ('abundances', 'copies', 'lengths')}
    pfam = {res: defaultdict(int) for res in ('abundances', 'copies', 'lengths')}

    ### Define helper functions.
    def update_dicts(funDict, funIdx):
        # abundances, copies, lengths and ignore_unclassified_fun are taken from the outer scope.
        funs = line[funIdx].replace('*','')
        funs = ['Unclassified'] if not funs else funs.strip(';').split(';') # So much fun!
        for fun in funs:
            if ignore_unclassified_fun and fun == 'Unclassified':
                continue
            # If we have a multi-KO annotation, split counts between all KOs.
            funDict['abundances'][fun] += abundances / len(funs)
            funDict['copies'][fun]     += copies # We treat every KO as an individual smaller gene: less size, less reads, one copy.
            funDict['lengths'][fun]    += lengths / len(funs)


    def tpm(funDict):
        # Calculate reads per kilobase.    
        fun_avgLengths = {fun: funDict['lengths'][fun] / funDict['copies'][fun] for fun in funDict['lengths']} # NaN appears if a fun has no copies in a sample.
        fun_rpk = {fun: funDict['abundances'][fun] / (fun_avgLengths[fun]/1000) for fun in funDict['abundances']}

        # Remove NaNs.
        for fun, rpk in fun_rpk.items():
            rpk[isnan(rpk)] = 0

        # Get tpm.    
        fun_tpm = normalize_abunds(fun_rpk, 1000000)
        return fun_tpm


    ### Do stuff.
    with open(orf_table) as infile:

        infile.readline() # Burn comment.
        header = infile.readline().strip().split('\t')
        idx =  {h: i for i,h in enumerate(header)}
        samples = [h for h in header if 'RAW READ COUNT' in h]
        sampleNames = [s.replace('RAW READ COUNT ', '') for s in samples]
        
        for line in infile:
            line = line.strip().split('\t')
            orf = line[idx['ORF']]
            if orfSet and orf not in orfSet:
                continue
            length = line[idx['LENGTH NT']]
            length = int(length) if length else 0 # Fix for rRNAs being in the ORFtable but having no length.
            if not length:
                print(line)
                continue # print and continue for debug info.

            abundances = array([int(line[idx[sample]]) for sample in samples])
            copies = (abundances>0).astype(int) # 1 copy if abund>0 in that sample, else 0.
            lengths = length * copies   # positive if abund>0 in that sample, else 0.
            orfs['abundances'][orf] = abundances
            orfs['copies'][orf] = copies
            orfs['lengths'][orf] = lengths

            if not nokegg:
                update_dicts(kegg, idx['KEGG ID'])
            if not nocog:
                update_dicts(cog, idx['COG ID'])
            if not nopfam:
                update_dicts(pfam, idx['PFAM'])

    # Calculate tpm.
    orfs['tpm'] = tpm(orfs) 
    if not nokegg:
        kegg['tpm'] = tpm(kegg)
    if not nocog:
        cog['tpm']  = tpm(cog)
    if not nopfam:
        pfam['tpm'] = tpm(pfam)

 
    return sampleNames, orfs, kegg, cog, pfam


def parse_tax_table(tax_table):
    orf_tax = {}
    orf_tax_wranks = {}
    with open(tax_table) as infile:
        infile.readline() # Burn comment.
        for line in infile:
            line = line.strip().split('\t')
            if len(line) == 1:
                orf, tax = line[0], 'n_Unclassified' # Add mock empty taxonomy, as the read is fully unclassified. 
            else:
                orf, tax = line
            orf_tax[orf], orf_tax_wranks[orf] = parse_tax_string(tax)
    return orf_tax, orf_tax_wranks


def parse_contig_table(contig_table):
    contig_tax = {}
    contig_tax_wranks = {}
    contig_abunds = {}
    with open(contig_table) as infile:
        infile.readline() # Burn comment.
        header = infile.readline().strip().split('\t')
        idx =  {h: i for i,h in enumerate(header)}
        samples = [h for h in header if 'Raw' in h]
        sampleNames = [s.replace('Raw ', '') for s in samples]
        for line in infile:
            line = line.strip().split('\t')
            contig, tax = line[idx['Contig ID']], line[idx['Tax']]
            if not tax:
                tax = 'n_Unclassified' # Add mock empty taxonomy, as the read is fully unclassified.
            contig_tax[contig], contig_tax_wranks[contig] = parse_tax_string(tax)
            contig_abunds[contig] = array([int(line[idx[sample]]) for sample in samples])
            
    return contig_abunds, contig_tax, contig_tax_wranks


def parse_tax_string(taxString):
    taxDict = dict([r.split('_', 1) for r in taxString.strip(';').split(';')]) # We only preserve the last "no_rank" taxonomy, but we don't care.
    taxList = []
    lastRankFound = ''
    for rank in reversed(TAXRANKS_SHORT): # From species to superkingdom.
        if rank in taxDict:
            lastRankFound = rank
            taxList.append(taxDict[rank])
        elif lastRankFound:
            # This rank is not present,  but we have a classification at a lower rank.
            # This happens in the NCBI tax e.g. for some eukaryotes, they are classified at the class but not at the phylum level.
            # We inherit lower rank taxonomies, as we actually have classified that ORF.
            taxList.append('{} (no {} in NCBI)'.format(taxDict[lastRankFound], TAXRANKS[TAXRANKS_SHORT.index(rank)]))
        else:
            # Neither this or lower ranks were present. The ORF is not classified at this level.
            pass
    # Now add strings for the unclassified ranks.
    unclassString = 'Unclassified {}'.format(taxList[0]) if taxList else 'Unclassified'
    while len(taxList) < 7:
        taxList.insert(0, unclassString)
    
    # Reverse to retrieve the original order.
    taxList.reverse()

    # Generate comprehensive taxonomy strings.
    taxList_wranks = []
    for i, rank in enumerate(TAXRANKS_SHORT):
        newStr = '{}_{}'.format(rank, taxList[i])
        if i>0:
            newStr = '{};{}'.format(taxList_wranks[-1], newStr)
        taxList_wranks.append(newStr)
            
    return taxList, taxList_wranks


def aggregate_tax_abunds(orf_abunds, orf_tax, rankIdx):
    tax_abunds = defaultdict(int)
    for orf, abunds in orf_abunds.items():
        if orf not in orf_tax:
            #print('{} had no hits against nr!'.format(orf))
            continue
        tax = orf_tax[orf][rankIdx]
        tax_abunds[tax] += abunds
    return tax_abunds


def normalize_abunds(abundDict, scale=1):
    abundPerSample = 0
    for row, abund in abundDict.items():
        abundPerSample += abund
    return {row: (scale * abund / abundPerSample) for row, abund in abundDict.items()}
    
    
    
    
    

def write_results(sampleNames, rowDict, outname):
    with open(outname, 'w') as outfile:
        outfile.write('\t{}\n'.format('\t'.join(sampleNames)))
        for row in sorted(rowDict):
            outfile.write('{}\t{}\n'.format(row, '\t'.join(map(str, rowDict[row]))))



def parse_args():
    parser = argparse.ArgumentParser(description='Aggregate SqueezeMeta results into tables', epilog='Fernando Puente-Sánchez (CNB) 2019\n')
    parser.add_argument('project_path', type=str, help='Base path of the SqueezeMeta project')
    parser.add_argument('output_dir', type=str, help='Output directory')
    parser.add_argument('--ignore_unclassified', action='store_true', help='Ignore ORFs without assigned functions in TPM calculation')

    return parser.parse_args()




if __name__ == '__main__':
    main(parse_args())

#!/usr/bin/env nextflow

log.info ""
log.info " NEXTFLOW ~  version ${workflow.nextflow.version} ${workflow.nextflow.build}"
log.info "-------------------------------------------------------------------------"
log.info "          Nextfow NeoAntigen Prediction Pipeline - nextNEOpi    "
log.info "-------------------------------------------------------------------------"
log.info ""
log.info " Features: "
log.info " - somatic variants from tumor + matched normal samples"
log.info " - CNV analysis"
log.info " - tumor muational burden"
log.info " - class I and class II HLA typing"
log.info " - gene fusion peptide prediction using RNAseq data"
log.info " - peptide MHC binding perdiction"
log.info " - clonality of neoantigens"
log.info " - expression of neoantigens"
log.info ""
log.info "-------------------------------------------------------------------------"
log.info "C O N F I G U R A T I O N"
log.info ""
log.info "Command Line: \t\t " + workflow.commandLine
log.info "Working Directory: \t " + params.workDir
log.info "Output Directory: \t " + params.outputDir
log.info ""
log.info "I N P U T"
log.info ""
if  (params.readsTumor != "NO_FILE") log.info " Reads Tumor: \t\t " + params.readsTumor
if  (params.readsNormal != "NO_FILE") log.info " Reads Normal: \t\t " + params.readsNormal
if  (params.readsRNAseq != "NO_FILE") log.info " Reads RNAseq: \t\t " + params.readsRNAseq
if  (params.customHLA != "NO_FILE") log.info " Custom HLA file: \t\t " + params.customHLA
log.info ""
log.info "Please check --help for further instruction"
log.info "-------------------------------------------------------------------------"

// Check if License(s) were accepted
params.accept_license = false

if (params.accept_license) {
    acceptLicense()
} else {
    checkLicense()
}

/*
________________________________________________________________________________

                            C O N F I G U R A T I O N
________________________________________________________________________________
*/
if (params.help) exit 0, helpMessage()

// switch for enable/disable processes (debug/devel only: use if(params.RUNTHIS) { .... })
params.RUNTHIS = false

// default is not to process a batchfile
params.batchFile = false

// default is not to get bams as input data
bamInput = false

// we got bam input on cmd line
if (! params.batchFile) {
    if(params.bamTumor != "NO_FILE" && params.readsTumor == "NO_FILE") {
        bamInput = true
    } else if(params.bamTumor == "NO_FILE" && params.readsTumor != "NO_FILE") {
        bamInput = false
    } else if(params.bamTumor != "NO_FILE" &&
              (params.readsTumor != "NO_FILE" ||
               params.readsNormal != "NO_FILE" ||
               params.readsRNAseq != "NO_FILE")) {
        exit 1, "Please do not provide tumor data as BAM and FASTQ"
    }
} else {
    batchCSV = file(params.batchFile).splitCsv(header:true)

    validFQfields = ["tumorSampleName",
                     "readsTumorFWD",
                     "readsTumorREV",
                     "normalSampleName",
                     "readsNormalFWD",
                     "readsNormalREV",
                     "readsRNAseqFWD",
                     "readsRNAseqREV",
                     "HLAfile",
                     "sex"]

    validBAMfields = ["tumorSampleName",
                      "bamTumor",
                      "normalSampleName",
                      "bamNormal",
                      "bamRNAseq",
                      "HLAfile",
                      "sex"]

    if (batchCSV.size() > 0) {

        if (batchCSV[0].keySet().sort() == validFQfields.sort()) {
            bamInput = false
        } else if (batchCSV[0].keySet().sort() == validBAMfields.sort()) {
            bamInput = true
        } else {
            exit 1, "Error: Incorrect fields in batch file, please check your batchFile"
        }
    } else {
        exit 1, "Error: No samples found, please check your batchFile"
    }

}

// set single_end variable to supplied param
single_end = false
single_end_RNA = false

// initialize RNAseq presence
have_RNAseq = false

// initialize RNA tag seq
have_RNA_tag_seq = params.RNA_tag_seq

// initialize custom HLA types presence
use_custom_hlas = false

// set and initialize the Exome capture kit
setExomeCaptureKit(params.exomeCaptureKit)

// set and check references and databases
reference = defineReference()
database = defineDatabases()

// create tmp dir and make sure we have the realpath for it
tmpDir = mkTmpDir(params.tmpDir)

/*--------------------------------------------------
  For workflow summary
---------------------------------------------------*/
// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if ( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ) {
    custom_runName = workflow.runName
}

// Summary
def summary = [:]
summary['Pipeline Name']                                   = 'icbi/nextNEOpi'
summary['Pipeline Version']                                = workflow.manifest.version
if(params.batchFile) summary['Batch file']                 = params.batchFile
if(params.readsNormal != "NO_FILE") summary['Reads normal fastq files'] = params.readsNormal
if(params.readsTumor != "NO_FILE") summary['Reads tumor fastq files']   = params.readsTumor
if(params.customHLA != "NO_FILE") summary['Custom HLA file']   = params.customHLA
summary['Sex']                        = params.sex
summary['Read length']                   = params.readLength
summary['Exome capture kit']             = params.exomeCaptureKit
summary['Fasta Ref']                     = params.references.RefFasta
summary['MillsGold']                     = params.databases.MillsGold
summary['hcSNPS1000G']                   = params.databases.hcSNPS1000G
summary['HapMap']                        = params.databases.HapMap
summary['Cosmic']                        = params.databases.Cosmic
summary['DBSNP']                         = params.databases.DBSNP
summary['GnomAD']                        = params.databases.GnomAD
summary['GnomADfull']                    = params.databases.GnomADfull
summary['KnownIndels']                   = params.databases.KnownIndels
summary['priority variant Caller']       = params.primaryCaller
summary['Mutect 1 and 2 minAD']          = params.minAD
summary['VarScan min_cov']               = params.min_cov
summary['VarScan min_cov_tumor']         = params.min_cov_tumor
summary['VarScan min_cov_normal']        = params.min_cov_normal
summary['VarScan min_freq_for_hom']      = params.min_freq_for_hom
summary['VarScan tumor_purity']          = params.tumor_purity
summary['VarScan somatic_pvalue']        = params.somatic_pvalue
summary['VarScan somatic_somaticpvalue'] = params.somatic_somaticpvalue
summary['VarScan strand_filter']         = params.strand_filter
summary['VarScan processSomatic_pvalue'] = params.processSomatic_pvalue
summary['VarScan max_normal_freq']       = params.max_normal_freq
summary['VarScan min_tumor_freq']        = params.min_tumor_freq
summary['VarScan min_map_q']             = params.min_map_q
summary['VarScan min_base_q']            = params.min_base_q
summary['VEP assembly']                  = params.vep_assembly
summary['VEP species']                   = params.vep_species
summary['VEP options']                   = params.vep_options
summary['Number of scatters']            = params.scatter_count
summary['Output dir']                    = params.outputDir
summary['Working dir']                   = workflow.workDir
summary['TMP dir']                       = tmpDir
summary['Current home']                  = "$HOME"
summary['Current user']                  = "$USER"
summary['Current path']                  = "$PWD"
summary['JAVA_Xmx']                      = params.JAVA_Xmx
summary['Picard maxRecordsInRam']        = params.maxRecordsInRam
summary['Script dir']                    = workflow.projectDir
summary['Config Profile']                = workflow.profile


if(params.email) summary['E-mail Address'] = params.email
log.info summary.collect { k,v -> "${k.padRight(30)}: $v" }.join("\n")
log.info "-------------------------------------------------------------------------"


def create_workflow_summary(summary) {

    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text  = """
    id: 'nextNEOpi-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'nextNEOpi Workflow Summary'
    section_href: 'https://github.com/icbi-lab/nextNEOpi'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k,v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

   return yaml_file
}
// End Summary


// set DNA and RNA sample counts to 0
dna_count = 0
rna_count = 0

// did not get a CSV batch file and input is not BAM: just run a single sample
if (! params.batchFile && ! bamInput) {
    // create channel with tumorSampleName/reads file set
    if (params.readsTumor != "NO_FILE") {
        // Sample name and reads file is passed via cmd line options
        // Sample name to use, if not given uses fastq file simpleName
        params.tumorSampleName  = "undefined"
        params.normalSampleName = "undefined"
        single_end = (file(params.readsTumor) instanceof LinkedList) ? false : true
        if(! single_end) {
            tumorSampleName = params.tumorSampleName != "undefined" ? params.tumorSampleName : file(params.readsTumor)[0].simpleName
        } else {
            tumorSampleName = params.tumorSampleName != "undefined" ? params.tumorSampleName : file(params.readsTumor).simpleName
        }
    } else  {
        exit 1, "No tumor sample defined"
    }

    if (params.readsNormal != "NO_FILE") {
        normal_libType = (file(params.readsNormal) instanceof LinkedList) ? "PE" : "SE"
        if ((normal_libType == "PE" && single_end) || (normal_libType == "SE" && ! single_end)) {
            exit 1, "Please do not mix pe and se for tumor/normal pairs: " + tumorSampleName + " - Not supported"
        }
        if(! single_end) {
            normalSampleName = params.normalSampleName != "undefined" ? params.normalSampleName : file(params.readsNormal)[0].simpleName
        } else {
            normalSampleName = params.normalSampleName != "undefined" ? params.normalSampleName : file(params.readsNormal).simpleName
        }

        Channel
                .fromFilePairs(params.readsTumor, size: -1)
                .map { reads -> tuple(tumorSampleName,
                                      normalSampleName,
                                      reads[1][0],
                                      (reads[1][1]) ? reads[1][1] : "NO_FILE_REV_T") }
                .into { raw_reads_tumor_ch;
                        fastqc_reads_tumor_ch }

        Channel
                .fromFilePairs(params.readsNormal, size: -1)
                .map { reads -> tuple(tumorSampleName,
                                      normalSampleName,
                                      reads[1][0],
                                      (reads[1][1]) ? reads[1][1] : "NO_FILE_REV_N") }
                .into { raw_reads_normal_ch; fastqc_reads_normal_ch }
    }  else  {
        exit 1, "No normal sample defined"
    }

    if (params.readsRNAseq) {
        single_end_RNA = (file(params.readsRNAseq) instanceof LinkedList) ? false : true
        Channel
                .fromFilePairs(params.readsRNAseq, size: -1)
                .map { reads -> tuple(tumorSampleName,
                                      normalSampleName,
                                      reads[1][0],
                                      (reads[1][1]) ? reads[1][1] : "NO_FILE_RNA_REV") }
                .into { raw_reads_tumor_neofuse_ch; fastqc_readsRNAseq_ch }
        have_RNAseq = true
    } else {
        have_RNAseq = false
    }
} else if ( params.batchFile && ! bamInput) {
    // batchfile ()= csv with sampleId and T/N reads was provided
    // create channel with all sampleId/reads file sets from the batch file
    // check if reverse reads are specified, if not set up single end processing
    // check if Normal reads are specified, if not set up exit with error
    // attention: if one of the samples is no-Normal or single end, all others
    // will be handled as such. You might want to process mixed sample data as
    // separate batches.
    batchCSV = file(params.batchFile).splitCsv(header:true)

    pe_dna_count = 0
    se_dna_count = 0
    pe_rna_count = 0
    se_rna_count = 0

    sexMap = [:]

    for ( row in batchCSV ) {
        if(row.sex && row.sex != "None") {
            if (row.sex in ["XX", "XY", "Female", "Male", "female", "male"]) {
               sexMap[row.tumorSampleName] = (row.sex == "Female" || row.sex == "XX" || row.sex == "female") ? "XX" : "XY"
            } else {
                exit 1, "Sex should be one of: XX, XY, Female, Male, female, male, got: " + row.sex
            }
        } else {
            println("WARNING: sex not specified assuming: XY")
            sexMap[row.tumorSampleName] = "XY"
        }

        if (row.readsTumorREV == "None") {
            single_end = true
            se_dna_count++
        } else {
            pe_dna_count++
        }

        if (! row.readsTumorFWD || row.readsTumorFWD == "None") {
            exit 1, "No tumor sample defined for " + row.tumorSampleName
        } else {
            dna_count++
        }

        if (! row.readsNormalFWD || row.readsNormalFWD == "None") {
            exit 1, "No normal sample defined for " + row.tumorSampleName
        }

        if (! row.readsRNAseqFWD || row.readsRNAseqFWD == "None") {
            have_RNAseq = false
        } else {
            have_RNAseq = true
            if (! row.readsRNAseqREV || row.readsRNAseqREV == "None") {
                single_end_RNA = true
                se_rna_count++
            } else {
                pe_rna_count++
            }
            rna_count++
        }

        if (row.HLAfile != "None" || row.HLAfile != "") {
            use_custom_hlas = true
        }
    }

    if ((dna_count != rna_count) && (rna_count != 0)) {
        exit 1, "Please do not mix samples with/without RNAseq data in batchfile"
    }

    if (pe_dna_count != 0 && se_dna_count != 0) {
        exit 1, "Please do not mix pe and se DNA read samples in batch file. Create a separate batch file for se and pe DNA samples"
    }

    if (pe_rna_count != 0 && se_rna_count != 0) {
        exit 1, "Please do not mix pe and se RNA read samples in batch file. Create a separate batch file for se and pe RNA samples"
    }

    Channel
            .fromPath(params.batchFile)
            .splitCsv(header:true)
            .map { row -> tuple(row.tumorSampleName,
                                row.normalSampleName,
                                file(row.readsTumorFWD),
                                file((row.readsTumorREV == "None") ? "NO_FILE_REV_T" : row.readsTumorREV)) }
            .into { raw_reads_tumor_ch;
                    fastqc_reads_tumor_ch }

    Channel
            .fromPath(params.batchFile)
            .splitCsv(header:true)
            .map { row -> tuple(row.tumorSampleName,
                                row.normalSampleName,
                                file(row.readsNormalFWD),
                                file((row.readsNormalREV == "None") ? "NO_FILE_REV_N" : row.readsNormalREV)) }
            .into { raw_reads_normal_ch; fastqc_reads_normal_ch }

    if (have_RNAseq) {
        Channel
                .fromPath(params.batchFile)
                .splitCsv(header:true)
                .map { row -> tuple(row.tumorSampleName,
                                    row.normalSampleName,
                                    file(row.readsRNAseqFWD),
                                    file(row.readsRNAseqREV)) }
                .into { raw_reads_tumor_neofuse_ch; fastqc_readsRNAseq_ch }
    }

    // user supplied HLA types (default: NO_FILE, will be checked in get_vhla)
    Channel
            .fromPath(params.batchFile)
            .splitCsv(header:true)
            .map { row -> tuple(row.tumorSampleName,
                                file((row.HLAfile == "None") ? "NO_FILE_HLA" : row.HLAfile)) }
            .set { custom_hlas_ch }
} else if (bamInput && ! params.batchFile) {
    // bam files provided on cmd line
    if (params.bamTumor != "NO_FILE") {
        params.tumorSampleName  = "undefined"
        tumorSampleName = params.tumorSampleName != "undefined" ? params.tumorSampleName : file(params.bamTumor).simpleName

    } else {
        exit 1, "No tumor sample defined"
    }
    if (params.bamNormal != "NO_FILE") {
        params.normalSampleName = "undefined"
        normalSampleName = params.normalSampleName != "undefined" ? params.normalSampleName : file(params.bamNormal).simpleName
    } else {
        exit 1, "No normal sample defined"
    }

    Channel
            .of(tuple(tumorSampleName,
                    normalSampleName,
                    file(params.bamTumor),
                    file(params.bamNormal)))
            .set { dna_bam_files }

    if (params.bamRNAseq) {
        Channel
                .of(tuple(tumorSampleName,
                          normalSampleName,
                          file(params.bamRNAseq)))
                .set { rna_bam_files }
        have_RNAseq = true
    }
} else {
    // bam files provided as batch file in CSV format
    // bams will be transformed to fastq files
    // library type SE/PE will be determinded automatically
    // mixing of PE/SE samples is not possible in a batch file,
    // but it is possible to provide PE DNA and SE RNA or vice versa
    batchCSV = file(params.batchFile).splitCsv(header:true)

    sexMap = [:]

    for ( row in batchCSV ) {
        if (row.sex && row.sex != "None") {
            if (row.sex in ["XX", "XY", "Female", "female", "Male", "male"]) {
                sexMap[row.tumorSampleName] = (row.sex == "Female" || row.sex == "XX" || row.sex == "female") ? "XX" : "XY"
            } else {
                exit 1, "Sex should be one of: XX, XY, Female, female, Male, male, got: " + row.sex
            }
        } else {
            println("WARNING: sex not specified assuming: XY")
            sexMap[row.tumorSampleName] = "XY"
        }

        if (! row.bamTumor || row.bamTumor == "" || row.bamTumor == "None") {
            exit 1, "No tumor sample defined for " + row.tumorSampleName
        }

        if (! row.bamNormal || row.bamNormal == "" || row.bamNormal == "None") {
            exit 1, "No normal sample defined for " + row.bamTumor
        }

        if (! row.bamRNAseq || row.bamRNAseq == "" || row.bamRNAseq == "None") {
            have_RNAseq = false
        } else {
            have_RNAseq = true
            rna_count++
        }

        if (row.HLAfile != "None" || row.HLAfile != "") {
            use_custom_hlas = true
        }

        dna_count++
    }


    Channel
            .fromPath(params.batchFile)
            .splitCsv(header:true)
            .map { row -> tuple(row.tumorSampleName,
                                row.normalSampleName,
                                file(row.bamTumor),
                                file(row.bamNormal)) }
            .set { dna_bam_files }

    if (have_RNAseq) {
        Channel
                .fromPath(params.batchFile)
                .splitCsv(header:true)
                .map { row -> tuple(row.tumorSampleName,
                                    row.normalSampleName,
                                    file(row.bamRNAseq)) }
                .set { rna_bam_files }
    }

    Channel
            .fromPath(params.batchFile)
            .splitCsv(header:true)
            .map { row -> tuple(row.tumorSampleName,
                                file((row.HLAfile == "None") ? "NO_FILE_HLA" : row.HLAfile)) }
            .set { custom_hlas_ch }

}

// set cutom HLA channel and sex channel if no batchFile was passed
if (! params.batchFile) {
    // user supplied HLA types (default: NO_FILE, will be checked in get_vhla)
    if (params.customHLA != "NO_FILE_HLA") {
        use_custom_hlas = true
    }

    Channel
            .of(tuple(
                    tumorSampleName,
                    file(params.customHLA)
                ))
            .set { custom_hlas_ch }

    sexMap = [:]

    if (params.sex in ["XX", "XY", "Female", "Male", "female", "male"]) {
        sexMap[tumorSampleName] = params.sex
    } else {
        exit 1, "Sex should be one of: XX, XY, Female, Male, female, male, got: " + params.sex
    }
}

// we do not support mixed batches of samples with and without RNAseq data
// separate batches are needed for this
if (params.batchFile && (dna_count != rna_count) && (rna_count != 0)) {
    exit 1, "Please do not mix samples with/without RNAseq data in batchfile"
}


// make empty RNAseq channels if no RNAseq data available
if (! have_RNAseq && params.batchFile) {
    Channel
            .fromPath(params.batchFile)
            .splitCsv(header:true)
            .map { row -> tuple(row.tumorSampleName,
                                row.normalSampleName,
                                file("NO_FILE_RNA_FWD"),
                                file("NO_FILE_RNA_REV")) }
            .into { raw_reads_tumor_neofuse_ch; fastqc_readsRNAseq_ch }

    Channel
            .fromPath(params.batchFile)
            .splitCsv(header:true)
            .map { row -> tuple(row.tumorSampleName,
                                file("NO_FILE_OPTI_RNA")) }
            .set { optitype_RNA_output }

    Channel
            .fromPath(params.batchFile)
            .splitCsv(header:true)
            .map { row -> tuple(row.tumorSampleName,
                                file("NO_FILE_HLAHD_RNA")) }
            .set { hlahd_output_RNA }

} else if (! have_RNAseq && ! params.batchFile ){
    Channel
            .of(tuple(tumorSampleName,
                        normalSampleName,
                        file("NO_FILE_RNA_FWD"),
                        file("NO_FILE_RNA_REV")))
            .into { raw_reads_tumor_neofuse_ch; fastqc_readsRNAseq_ch }

    Channel
        .of(tuple(
            tumorSampleName,
            "NO_FILE_OPTI_RNA"
        ))
        .set { optitype_RNA_output }

    Channel
        .of(tuple(
            tumorSampleName,
            "NO_FILE_HLAHD_RNA"
        ))
        .into { hlahd_output_RNA }
}

// optional panel of normals file
pon_file = file(params.mutect2ponFile)

scatter_count = Channel.from(params.scatter_count)
padding = params.readLength + 100

MIXCR         = ( params.MIXCR != "" ) ? file(params.MIXCR) : ""
MiXMHC2PRED   = ( params.MiXMHC2PRED != "" ) ? file(params.MiXMHC2PRED) : ""

// check HLAHD & OptiType
have_HLAHD = false
run_OptiType = (params.disable_OptiType) ? false : true

if (params.HLAHD_DIR != "") {
    HLAHD = file(params.HLAHD_DIR + "/bin/hlahd.sh")
    if (checkToolAvailable(HLAHD, "exists", "warn")) {
        HLAHD_DIR  = file(params.HLAHD_DIR)
        HLAHD_PATH = HLAHD_DIR + "/bin"
        have_HLAHD = true
    }
}
if (! have_HLAHD && run_OptiType) {
    log.warn "WARNING: HLAHD not available - can not predict Class II neoepitopes"
} else if (! have_HLAHD && ! run_OptiType && use_custom_hlas) {
    log.warn "WARNING: HLAHD not available and OptiType disabled - using only user supplied HLA types"
} else if (! have_HLAHD && ! run_OptiType && ! use_custom_hlas) {
    exit 1, "ERROR: HLAHD not available and OptiType disabled - can not predict HLA types"
}

// check if all tools are installed when not running conda or singularity
have_vep = false
if (! workflow.profile.contains('conda') && ! workflow.profile.contains('singularity')) {
    def execTools = ["fastqc", "fastp", "bwa", "samtools", "sambamba", "gatk", "vep", "bam-readcount",
                     "perl", "bgzip", "tabix", "bcftools", "yara_mapper", "python", "cnvkit.py",
                     "OptiTypePipeline.py", "alleleCounter", "freec", "Rscript", "java", "multiqc",
                     "sequenza-utils"]

    for (tool in execTools) {
        checkToolAvailable(tool, "inPath", "error")
    }

    VARSCAN = "java " + params.JAVA_Xmx + " -jar " + file(params.VARSCAN)
    have_vep = true
} else {
    VARSCAN = "varscan " + params.JAVA_Xmx
}

// check if we have mutect1 installed
have_Mutect1 = false
if (params.MUTECT1 != "" && file(params.MUTECT1) && params.JAVA7 != "" && file(params.JAVA7)) {
    if(checkToolAvailable(params.JAVA7, "inPath", "warn") && checkToolAvailable(params.MUTECT1, "exists", "warn")) {
        JAVA7 = file(params.JAVA7)
        MUTECT1 = file(params.MUTECT1)
        have_Mutect1 = true
    }
}

// check if we have GATK3 installed
have_GATK3 = false
if (file(params.GATK3) && file(params.JAVA8) && ! workflow.profile.contains('conda') && ! workflow.profile.contains('singularity')) {
    if(checkToolAvailable(params.JAVA8, "inPath", "warn") && checkToolAvailable(params.GATK3, "exists", "warn")) {
        JAVA8 = file(params.JAVA8)
        GATK3 = file(params.GATK3)
        have_GATK3 = true
    }
} else if (workflow.profile.contains('singularity')) {
    JAVA8 = "java"
    GATK3 = "/usr/local/opt/gatk-3.8/GenomeAnalysisTK.jar"
    have_GATK3 = true
} else if (workflow.profile.contains('conda')) {
    JAVA8 = "java"
    GATK3 = "\$CONDA_PREFIX/opt/gatk-3.8/GenomeAnalysisTK.jar"
    have_GATK3 = true
}


/*
________________________________________________________________________________

                                P R O C E S S E S
________________________________________________________________________________
*/

/*
*********************************************
**       P R E P R O C E S S I N G         **
*********************************************
*/

// Handle BAM input files. We need to convert BAMs to Fastq
if(bamInput) {
    process check_DNA_PE {
        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(bamTumor),
            file(bamNormal)
        ) from dna_bam_files

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(bamTumor),
            file(bamNormal),
            stdout
        ) into check_DNA_seqLib_ch


        script:
        """
        check_pe.py $bamTumor $bamNormal
        """
    }
    (bam_DNA_ch, check_DNA_seqLib_ch) = check_DNA_seqLib_ch.into(2)
    check_seqLibTypes_ok(check_DNA_seqLib_ch, "DNA")


    if (have_RNAseq) {
        process check_RNA_PE {
            label 'nextNEOpiENV'

            tag "$TumorReplicateId"

            input:
            set(
                TumorReplicateId,
                NormalReplicateId,
                file(bamRNAseq),
            ) from rna_bam_files

            output:
            set(
                TumorReplicateId,
                NormalReplicateId,
                file(bamRNAseq),
                stdout
            ) into check_RNA_seqLib_ch


            script:
            """
            check_pe.py $bamRNAseq
            """
        }
        (bam_RNA_ch, check_RNA_seqLib_ch) = check_RNA_seqLib_ch.into(2)
        check_seqLibTypes_ok(check_RNA_seqLib_ch, "RNA")
    }


    process bam2fastq_DNA {
        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "${params.outputDir}/analyses/$TumorReplicateId/01_preprocessing",
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(bamTumor),
            file(bamNormal),
            libType
        ) from bam_DNA_ch


        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${TumorReplicateId}_FWD.fastq.gz"),
            file("${tumorDNA_rev_fq}")
        ) into (
            raw_reads_tumor_ch,
            fastqc_reads_tumor_ch
        )

        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${NormalReplicateId}_FWD.fastq.gz"),
            file("${normalDNA_rev_fq}")
        ) into (
            raw_reads_normal_ch,
            fastqc_reads_normal_ch
        )

        script:
        if (libType == "MIXED") {
            exit 1, "Please do not mix pe and se for tumor/normal pairs: " + TumorReplicateId + " - Not supported"
        } else if (libType == "PE") {
            tumorDNA_rev_fq = "${TumorReplicateId}_REV.fastq.gz"
            normalDNA_rev_fq = "${NormalReplicateId}_REV.fastq.gz"
        } else {
            tumorDNA_rev_fq = "None"
            normalDNA_rev_fq = "None"
        }

        if (libType == "PE")
            """
            samtools sort -@ ${task.cpus} -m ${params.STperThreadMem} -l 0 -n ${bamTumor} | \\
            samtools fastq \\
                -@ ${task.cpus} \\
                -c 5 \\
                -1 ${TumorReplicateId}_FWD.fastq.gz \\
                -2 ${TumorReplicateId}_REV.fastq.gz \\
                -0 /dev/null -s /dev/null \\
                -n \\
                /dev/stdin

            samtools sort -@ ${task.cpus} -m ${params.STperThreadMem} -l 0 -n ${bamNormal} | \\
            samtools fastq \\
                -@ ${task.cpus} \\
                -c 5 \\
                -1 ${NormalReplicateId}_FWD.fastq.gz \\
                -2 ${NormalReplicateId}_REV.fastq.gz \\
                -0 /dev/null -s /dev/null \\
                -n \\
                /dev/stdin
            """
        else if (libType == "SE")
            """
            samtools fastq \\
                -@ ${task.cpus} \\
                -n \\
                ${bamTumor} | \\
                bgzip -@ ${task.cpus} -c /dev/stdin > ${TumorReplicateId}_FWD.fastq.gz

            samtools fastq \\
                -@ ${task.cpus} \\
                -n \\
                ${bamNormal} | \\
                bgzip -@ ${task.cpus} -c /dev/stdin > ${TumorReplicateId}_FWD.fastq.gz

            touch None
            """
    }

    if (have_RNAseq) {
        process bam2fastq_RNA {
            label 'nextNEOpiENV'

            tag "$TumorReplicateId"

            publishDir "${params.outputDir}/analyses/$TumorReplicateId/01_preprocessing",
                mode: params.publishDirMode

            input:
            set(
                TumorReplicateId,
                NormalReplicateId,
                file(bamRNAseq),
                libType
            ) from bam_RNA_ch


            output:
            set(
                TumorReplicateId,
                NormalReplicateId,
                file("${TumorReplicateId}_RNA_FWD.fastq.gz"),
                file("${tumorRNA_rev_fq}")
            ) into (
                raw_reads_tumor_neofuse_ch,
                fastqc_readsRNAseq_ch
            )

            script:
            if (libType == "PE") {
                tumorRNA_rev_fq = "${TumorReplicateId}_RNA_REV.fastq.gz"
            } else if (libType == "SE") {
                tumorRNA_rev_fq = "None"
            } else {
                exit 1, "An error occured: " + TumorReplicateId + ": RNAseq library type not SE or PE."
            }

            if (libType == "PE")
                """
                samtools sort -@ ${task.cpus} -m ${params.STperThreadMem} -l 0 -n ${bamRNAseq} | \\
                samtools fastq \\
                    -@ ${task.cpus} \\
                    -c 5 \\
                    -1 ${TumorReplicateId}_RNA_FWD.fastq.gz \\
                    -2 ${TumorReplicateId}_RNA_REV.fastq.gz \\
                    -0 /dev/null -s /dev/null \\
                    -n \\
                /dev/stdin
                """
            else if (libType == "SE")
                """
                samtools fastq \\
                    -@ ${task.cpus} \\
                    -n \\
                    ${bamRNAseq} | \\
                    bgzip -@ ${task.cpus} -c /dev/stdin > ${TumorReplicateId}_RNA_FWD.fastq.gz

                touch None
                """
        }
    }
}
// END BAM input handling

// Common region files preparation for faster processing
if (params.WES) {
    process 'RegionsBedToIntervalList' {

        label 'nextNEOpiENV'

        tag 'RegionsBedToIntervalList'

        publishDir "$params.outputDir/supplemental/00_prepare_Intervals/",
            mode: params.publishDirMode

        input:
        set(
            file(RefDict),
            file(RegionsBed)
        ) from Channel.value(
            [ reference.RefDict,
            reference.RegionsBed ]
        )

        output:
        file(
            "${RegionsBed.baseName}.interval_list"
        ) into (
            RegionsBedToIntervalList_out_ch0,
            RegionsBedToIntervalList_out_ch1
        )

        script:
        """
        gatk --java-options ${params.JAVA_Xmx} BedToIntervalList \\
            -I ${RegionsBed} \\
            -O ${RegionsBed.baseName}.interval_list \\
            -SD $RefDict
        """
    }

    process 'BaitsBedToIntervalList' {

        label 'nextNEOpiENV'

        tag 'BaitsBedToIntervalList'

        publishDir "$params.outputDir/supplemental/00_prepare_Intervals/",
            mode: params.publishDirMode

        input:
        set(
            file(RefDict),
            file(BaitsBed)
        ) from Channel.value(
            [ reference.RefDict,
            reference.BaitsBed ]
        )

        output:
        file(
            "${BaitsBed.baseName}.interval_list"
        ) into BaitsBedToIntervalList_out_ch0

        script:
        """
        gatk --java-options ${params.JAVA_Xmx} BedToIntervalList \\
            -I ${BaitsBed} \\
            -O ${BaitsBed.baseName}.interval_list \\
            -SD $RefDict
        """
    }
} else {
    RegionsBedToIntervalList_out_ch0 = Channel.of('NO_FILE')
    RegionsBedToIntervalList_out_ch1 = Channel.empty()
    BaitsBedToIntervalList_out_ch0 = Channel.empty()
}

process 'preprocessIntervalList' {

    label 'nextNEOpiENV'

    tag 'preprocessIntervalList'

    publishDir "$params.outputDir/supplemental/00_prepare_Intervals/",
        mode: params.publishDirMode

    input:
    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )
    file(interval_list) from RegionsBedToIntervalList_out_ch0

    output:
    file(
        "${interval_list.baseName}_merged_padded.interval_list"
    ) into (
        preprocessIntervalList_out_ch0,
        preprocessIntervalList_out_ch1,
        preprocessIntervalList_out_ch2,
        preprocessIntervalList_out_ch3,
        preprocessIntervalList_out_ch4,
        preprocessIntervalList_out_ch5,
        preprocessIntervalList_out_ch6,
        preprocessIntervalList_out_ch7,
        preprocessIntervalList_out_ch8
    )

    script:
    if(params.WES)
        """
        gatk PreprocessIntervals \\
            -R $RefFasta \\
            -L ${interval_list} \\
            --bin-length 0 \\
            --padding ${padding} \\
            --interval-merging-rule OVERLAPPING_ONLY \\
            -O ${interval_list.baseName}_merged_padded.interval_list
        """
    else
        """
        gatk --java-options ${params.JAVA_Xmx} ScatterIntervalsByNs \\
            --REFERENCE $RefFasta \\
            --OUTPUT_TYPE ACGT \\
            --OUTPUT ${interval_list.baseName}_merged_padded.interval_list
        """
}

// Splitting interval file in 20(default) files for scattering Mutect2
process 'SplitIntervals' {

    label 'nextNEOpiENV'

    tag "SplitIntervals"

    publishDir "$params.outputDir/supplemental/00_prepare_Intervals/SplitIntervals/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    file(IntervalsList) from preprocessIntervalList_out_ch0

    val x from scatter_count

    output:
    file(
        "${IntervalName}/*-scattered.interval_list"
    ) into (
        SplitIntervals_out_ch0,
        SplitIntervals_out_ch1,
        SplitIntervals_out_ch2,
        SplitIntervals_out_scatterBaseRecalTumorGATK4_ch,
        SplitIntervals_out_scatterTumorGATK4applyBQSRS_ch,
        SplitIntervals_out_scatterBaseRecalNormalGATK4_ch,
        SplitIntervals_out_scatterNormalGATK4applyBQSRS_ch,
        SplitIntervals_out_ch3,
        SplitIntervals_out_ch4,
        SplitIntervals_out_ch5,
        SplitIntervals_out_ch6,
    )
    val("${IntervalName}") into SplitIntervals_out_ch0_Name

    script:
    IntervalName = IntervalsList.baseName
    """
    mkdir -p ${tmpDir}

    gatk SplitIntervals \\
        --tmp-dir ${tmpDir} \\
        -R ${RefFasta}  \\
        -scatter ${x} \\
        --interval-merging-rule ALL \\
        --subdivision-mode BALANCING_WITHOUT_INTERVAL_SUBDIVISION_WITH_OVERFLOW \\
        -L ${IntervalsList} \\
        -O ${IntervalName}

    """
}


// convert padded interval list to Bed file (used by varscan)
// generate a padded tabix indexed region BED file for strelka
process 'IntervalListToBed' {

    label 'nextNEOpiENV'

    tag 'BedFromIntervalList'

    publishDir "$params.outputDir/supplemental/00_prepare_Intervals/",
        mode: params.publishDirMode

    input:
        file(paddedIntervalList) from preprocessIntervalList_out_ch1

    output:
    tuple(
        file("${paddedIntervalList.baseName}.bed.gz"),
        file("${paddedIntervalList.baseName}.bed.gz.tbi")
    ) into (
        RegionsBedToTabix_out_ch0,
        RegionsBedToTabix_out_ch1
    )

    script:
    """
    gatk --java-options ${params.JAVA_Xmx} IntervalListToBed \\
        -I ${paddedIntervalList} \\
        -O ${paddedIntervalList.baseName}.bed

    bgzip -c ${paddedIntervalList.baseName}.bed > ${paddedIntervalList.baseName}.bed.gz &&
    tabix -p bed ${paddedIntervalList.baseName}.bed.gz
    """
}

// convert scattered padded interval list to Bed file (used by varscan)
process 'ScatteredIntervalListToBed' {

    label 'nextNEOpiENV'

    tag 'ScatteredIntervalListToBed'

    publishDir "$params.outputDir/supplemental/00_prepare_Intervals/SplitIntervals/${IntervalName}",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        val(IntervalName),
        file(IntervalsList)
    ) from SplitIntervals_out_ch0_Name
        .combine(
            SplitIntervals_out_ch0.flatten()
        )


    output:
    file(
        "*.bed"
    ) into (
        ScatteredIntervalListToBed_out_ch0,
        ScatteredIntervalListToBed_out_ch1
    )

    script:
    """
    gatk --java-options ${params.JAVA_Xmx} IntervalListToBed \\
        -I ${IntervalsList} \\
        -O ${IntervalsList.baseName}.bed
    """
}

// FastQC
process FastQC {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "${params.outputDir}/analyses/$TumorReplicateId/QC/fastqc",
        mode: params.publishDirMode,
        saveAs: { filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"}

    if (have_RNAseq) {
        if (!single_end && !single_end_RNA) {
            cpus = 6
        } else if (!single_end && single_end_RNA) {
            cpus = 5
        } else if (single_end && !single_end_RNA) {
            cpus = 4
        } else if (single_end && single_end_RNA) {
            cpus = 3
        }
    } else {
        if (!single_end) {
            cpus = 4
        } else {
            cpus = 2
        }
    }

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(tumor_readsFWD),
        file(tumor_readsREV),
        file(normal_readsFWD),
        file(normal_readsREV),
        file(readsRNAseq_FWD),
        file(readsRNAseq_REV)
    ) from fastqc_reads_tumor_ch
        .combine(fastqc_reads_normal_ch, by: [0,1])
        .combine(fastqc_readsRNAseq_ch, by: [0,1])


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("*_fastqc*")
    ) into ch_fastqc // multiQC

    script:
    tumor_readsFWD_simpleName = tumor_readsFWD.getSimpleName()
    normal_readsFWD_simpleName = normal_readsFWD.getSimpleName()
    tumor_readsFWD_ext = tumor_readsFWD.getExtension()
    normal_readsFWD_ext = normal_readsFWD.getExtension()

    tumor_readsFWD_ext = (tumor_readsFWD_ext == "gz") ? "fastq.gz" : tumor_readsFWD_ext
    normal_readsFWD_ext = (normal_readsFWD_ext == "gz") ? "fastq.gz" : normal_readsFWD_ext

    if (! single_end) {
        tumor_readsREV_simpleName = tumor_readsREV.getSimpleName()
        normal_readsREV_simpleName = normal_readsREV.getSimpleName()
        tumor_readsREV_ext = tumor_readsREV.getExtension()
        normal_readsREV_ext = normal_readsREV.getExtension()

        tumor_readsREV_ext = (tumor_readsREV_ext == "gz") ? "fastq.gz" : tumor_readsREV_ext
        normal_readsREV_ext = (normal_readsREV_ext == "gz") ? "fastq.gz" : normal_readsREV_ext
    }


    if (have_RNAseq) {
        readsRNAseq_FWD_simpleName = readsRNAseq_FWD.getSimpleName()
        readsRNAseq_FWD_ext = readsRNAseq_FWD.getExtension()
        readsRNAseq_FWD_ext = (readsRNAseq_FWD_ext == "gz") ? "fastq.gz" : readsRNAseq_FWD_ext

        if (! single_end_RNA) {
            readsRNAseq_REV_simpleName = readsRNAseq_REV.getSimpleName()
            readsRNAseq_REV_ext = readsRNAseq_REV.getExtension()

            readsRNAseq_REV_ext = (readsRNAseq_REV_ext == "gz") ? "fastq.gz" : readsRNAseq_REV_ext
        }
    }

    if (single_end && single_end_RNA && have_RNAseq)
        """
        ln -s $tumor_readsFWD ${TumorReplicateId}_R1.${tumor_readsFWD_ext}
        ln -s $normal_readsFWD ${NormalReplicateId}_R1.${normal_readsFWD_ext}
        ln -s $readsRNAseq_FWD ${TumorReplicateId}_RNA_R1.${readsRNAseq_FWD_ext}

        fastqc --quiet --threads ${task.cpus} \\
            ${TumorReplicateId}_R1.${tumor_readsFWD_ext} \\
            ${NormalReplicateId}_R1.${normal_readsFWD_ext} \\
            ${TumorReplicateId}_RNA_R1.${readsRNAseq_FWD_ext}
        """
    else if (!single_end && !single_end_RNA && have_RNAseq)
        """
        ln -s $tumor_readsFWD ${TumorReplicateId}_R1.${tumor_readsFWD_ext}
        ln -s $normal_readsFWD ${NormalReplicateId}_R1.${normal_readsFWD_ext}
        ln -s $tumor_readsREV ${TumorReplicateId}_R2.${tumor_readsREV_ext}
        ln -s $normal_readsREV ${NormalReplicateId}_R2.${normal_readsREV_ext}

        ln -s $readsRNAseq_FWD ${TumorReplicateId}_RNA_R1.${readsRNAseq_FWD_ext}
        ln -s $readsRNAseq_REV ${TumorReplicateId}_RNA_R2.${readsRNAseq_REV_ext}

        fastqc --quiet --threads ${task.cpus} \\
            ${TumorReplicateId}_R1.${tumor_readsFWD_ext} ${TumorReplicateId}_R2.${tumor_readsREV_ext} \\
            ${NormalReplicateId}_R1.${normal_readsFWD_ext} ${NormalReplicateId}_R2.${normal_readsREV_ext} \\
            ${TumorReplicateId}_RNA_R1.${readsRNAseq_FWD_ext} ${TumorReplicateId}_RNA_R2.${readsRNAseq_REV_ext}
        """
    else if (!single_end && single_end_RNA && have_RNAseq)
        """
        ln -s $tumor_readsFWD ${TumorReplicateId}_R1.${tumor_readsFWD_ext}
        ln -s $normal_readsFWD ${NormalReplicateId}_R1.${normal_readsFWD_ext}
        ln -s $tumor_readsREV ${TumorReplicateId}_R2.${tumor_readsREV_ext}
        ln -s $normal_readsREV ${NormalReplicateId}_R2.${normal_readsREV_ext}

        ln -s $readsRNAseq_FWD ${TumorReplicateId}_RNA_R1.${readsRNAseq_FWD_ext}

        fastqc --quiet --threads ${task.cpus} \\
            ${TumorReplicateId}_R1.${tumor_readsFWD_ext} ${TumorReplicateId}_R2.${tumor_readsREV_ext} \\
            ${NormalReplicateId}_R1.${normal_readsFWD_ext} ${NormalReplicateId}_R2.${normal_readsREV_ext} \\
            ${TumorReplicateId}_RNA_R1.${readsRNAseq_FWD_ext}
        """
    else if (single_end && !single_end_RNA && have_RNAseq)
        """
        ln -s $tumor_readsFWD ${TumorReplicateId}.${tumor_readsFWD_ext}
        ln -s $normal_readsFWD ${NormalReplicateId}.${normal_readsFWD_ext}

        ln -s $readsRNAseq_FWD ${TumorReplicateId}_RNA_R1.${readsRNAseq_FWD_ext}
        ln -s $readsRNAseq_REV ${TumorReplicateId}_RNA_R2.${readsRNAseq_REV_ext}

        fastqc --quiet --threads ${task.cpus} \\
            ${TumorReplicateId}_R1.${tumor_readsFWD_ext} \\
            ${NormalReplicateId}_R1.${normal_readsFWD_ext} \\
            ${TumorReplicateId}_RNA_R1.${readsRNAseq_FWD_ext} ${TumorReplicateId}_RNA_R2.${readsRNAseq_REV_ext}
        """
    else if (single_end && !have_RNAseq)
        """
        ln -s $tumor_readsFWD ${TumorReplicateId}_R1.${tumor_readsFWD_ext}
        ln -s $normal_readsFWD ${NormalReplicateId}_R1.${normal_readsFWD_ext}

        fastqc --quiet --threads ${task.cpus} \\
            ${TumorReplicateId}_R1.${tumor_readsFWD_ext} \\
            ${NormalReplicateId}_R1.${normal_readsFWD_ext}
        """
    else if (!single_end && !have_RNAseq)
        """
        ln -s $tumor_readsFWD ${TumorReplicateId}_R1.${tumor_readsFWD_ext}
        ln -s $normal_readsFWD ${NormalReplicateId}_R1.${normal_readsFWD_ext}
        ln -s $tumor_readsREV ${TumorReplicateId}_R2.${tumor_readsREV_ext}
        ln -s $normal_readsREV ${NormalReplicateId}_R2.${normal_readsREV_ext}

        fastqc --quiet --threads ${task.cpus} \\
            ${TumorReplicateId}_R1.${tumor_readsFWD_ext} ${TumorReplicateId}_R2.${tumor_readsREV_ext} \\
            ${NormalReplicateId}_R1.${normal_readsFWD_ext} ${NormalReplicateId}_R2.${normal_readsREV_ext}
        """

}

// adapter trimming Tumor
if (params.trim_adapters) {
    process fastp_tumor {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/",
            mode: params.publishDirMode,
            saveAs: {
                filename ->
                    if(filename.indexOf(".json") > 0) {
                        return "QC/fastp/$filename"
                    } else if(filename.indexOf("NO_FILE") >= 0) {
                        return null
                    } else {
                        return  "01_preprocessing/$filename"
                    }
            }

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(tumor_readsFWD),
            file(tumor_readsREV)
        ) from raw_reads_tumor_ch

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${TumorReplicateId}_trimmed_R1.fastq.gz"),
            file("${trimmedReads_2}")
        ) into (
            reads_tumor_ch,
            reads_tumor_uBAM_ch,
            reads_tumor_mixcr_DNA_ch,
            fastqc_reads_tumor_trimmed_ch
        )
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("*.json")
        ) into ch_fastp_tumor // multiQC


        script:
        trimmedReads_2 = (single_end) ? "NO_FILE_T" : TumorReplicateId + "_trimmed_R2.fastq.gz"

        def fastpAdapter = ''
        if(params.adapterSeqFile != false) {
            adapterSeqFile = Channel.fromPath(params.adapterSeqFile)
            fastpAdapter = "--adapter_fasta $adapterSeqFile"
        } else {
            if(params.adapterSeq != false) {
                adapterSeq   = Channel.value(params.adapterSeq)
                fastpAdapter = "--adapter_sequence " + adapterSeq.getVal()

                if(params.adapterSeqR2 != false) {
                    adapterSeqR2   = Channel.value(params.adapterSeqR2)
                    fastpAdapter += " --adapter_sequence_r2 " + adapterSeqR2.getVal()
                }
            }
        }

        if(single_end)
            """
            fastp --thread ${task.cpus} \\
                --in1 ${tumor_readsFWD} \\
                --out1 ${TumorReplicateId}_trimmed_R1.fastq.gz \\
                --json ${TumorReplicateId}_fastp.json \\
                ${fastpAdapter} \\
                ${params.fastpOpts}
            touch NO_FILE_T
            """
        else
            """
            fastp --thread ${task.cpus} \\
                --in1 ${tumor_readsFWD} \\
                --in2 ${tumor_readsREV} \\
                --out1 ${TumorReplicateId}_trimmed_R1.fastq.gz \\
                --out2 ${TumorReplicateId}_trimmed_R2.fastq.gz \\
                --json ${TumorReplicateId}_fastp.json \\
                ${fastpAdapter} \\
                ${params.fastpOpts}
            """
    }

    process fastp_normal {

        label 'nextNEOpiENV'

        tag "$NormalReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/",
            mode: params.publishDirMode,
            saveAs: {
                filename ->
                    if(filename.indexOf(".json") > 0) {
                        return "QC/fastp/$filename"
                    } else if(filename.indexOf("NO_FILE") >= 0) {
                        return null
                    } else {
                        return  "01_preprocessing/$filename"
                    }
            }

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(normal_readsFWD),
            file(normal_readsREV)
        ) from raw_reads_normal_ch

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${NormalReplicateId}_trimmed_R1.fastq.gz"),
            file("${trimmedReads_2}")
        ) into (
            reads_normal_ch,
            reads_normal_uBAM_ch,
            reads_normal_mixcr_DNA_ch,
            fastqc_reads_normal_trimmed_ch
        )
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("*.json")
        ) into ch_fastp_normal // multiQC


        script:
        trimmedReads_2 = (single_end) ? "NO_FILE_N" : NormalReplicateId + "_trimmed_R2.fastq.gz"

        def fastpAdapter = ''
        if(params.adapterSeqFile != false) {
            adapterSeqFile = Channel.fromPath(params.adapterSeqFile)
            fastpAdapter = "--adapter_fasta $adapterSeqFile"
        } else {
            if(params.adapterSeq != false) {
                adapterSeq   = Channel.value(params.adapterSeq)
                fastpAdapter = "--adapter_sequence " + adapterSeq.getVal()

                if(params.adapterSeqR2 != false) {
                    adapterSeqR2   = Channel.value(params.adapterSeqR2)
                    fastpAdapter += " --adapter_sequence_r2 " + adapterSeqR2.getVal()
                }
            }
        }

        if(single_end)
            """
            fastp --thread ${task.cpus} \\
                --in1 ${normal_readsFWD} \\
                --out1 ${NormalReplicateId}_trimmed_R1.fastq.gz \\
                --json ${NormalReplicateId}_fastp.json \\
                ${fastpAdapter} \\
                ${params.fastpOpts}
            touch NO_FILE_N
            """
        else
            """
            fastp --thread ${task.cpus} \\
                --in1 ${normal_readsFWD} \\
                --in2 ${normal_readsREV} \\
                --out1 ${NormalReplicateId}_trimmed_R1.fastq.gz \\
                --out2 ${NormalReplicateId}_trimmed_R2.fastq.gz \\
                --json ${NormalReplicateId}_fastp.json \\
                ${fastpAdapter} \\
                ${params.fastpOpts}
            """
    }


    // FastQC after adapter trimming
    process FastQC_trimmed {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "${params.outputDir}/analyses/$TumorReplicateId/QC/fastqc/",
            mode: params.publishDirMode,
            saveAs: { filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"}

        if (single_end) {
            cpus = 2
        } else {
            cpus = 4
        }

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(tumor_readsFWD),
            file(tumor_readsREV),
            file(normal_readsFWD),
            file(normal_readsREV)
        ) from fastqc_reads_tumor_trimmed_ch
            .combine(fastqc_reads_normal_trimmed_ch, by: [0,1])


        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("*_fastqc*")
        ) into ch_fastqc_trimmed // multiQC

        script:
        if (single_end)
            """
            fastqc --quiet --threads ${task.cpus} \\
                ${tumor_readsFWD} \\
                ${normal_readsFWD}
            """
        else
            """
            fastqc --quiet --threads ${task.cpus} \\
                ${tumor_readsFWD} ${tumor_readsREV} \\
                ${normal_readsFWD} ${normal_readsREV}
            """
    }
} else { // no adapter trimming
    (
        reads_tumor_ch,
        reads_tumor_uBAM_ch,
        reads_tumor_mixcr_DNA_ch,
        ch_fastqc_trimmed
    ) = raw_reads_tumor_ch.into(4)

    (
        reads_normal_ch,
        reads_normal_uBAM_ch,
        reads_normal_mixcr_DNA_ch
    ) = raw_reads_normal_ch.into(3)

    ch_fastqc_trimmed = ch_fastqc_trimmed
                            .map{ it -> tuple(it[0], it[1], "")}

    (ch_fastp_normal, ch_fastp_tumor, ch_fastqc_trimmed) = ch_fastqc_trimmed.into(3)
}

// adapter trimming RNAseq
if (params.trim_adapters_RNAseq && have_RNAseq) {
    process fastp_RNAseq {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/",
            mode: params.publishDirMode,
            saveAs: {
                filename ->
                    if(filename.indexOf(".json") > 0) {
                        return "QC/fastp/$filename"
                    } else if(filename.indexOf("NO_FILE") >= 0) {
                        return null
                    } else {
                        return  "01_preprocessing/$filename"
                    }
            }

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(readsRNAseq_FWD),
            file(readsRNAseq_REV),
        ) from raw_reads_tumor_neofuse_ch

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${TumorReplicateId}_RNA_trimmed_R1.fastq.gz"),
            file("${trimmedReads_2}")
        ) into (
            reads_tumor_neofuse_ch,
            reads_tumor_optitype_ch,
            reads_tumor_hlahd_RNA_ch,
            reads_tumor_mixcr_RNA_ch,
            fastqc_readsRNAseq_trimmed_ch
        )
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("*.json")
        ) into ch_fastp_RNAseq // multiQC

        script:
        trimmedReads_2 = (single_end_RNA) ? "NO_FILE" : TumorReplicateId + "_RNA_trimmed_R2.fastq.gz"


        def fastpAdapter = ''
        if(params.adapterSeqFileRNAseq != false) {
            adapterSeqFile = Channel.fromPath(params.adapterSeqFileRNAseq)
            fastpAdapter = "--adapter_fasta $adapterSeqFile"
        } else {
            if(params.adapterSeqRNAseq != false) {
                adapterSeq   = Channel.value(params.adapterSeqRNAseq)
                fastpAdapter = "--adapter_sequence " + adapterSeq.getVal()

                if(params.adapterSeqR2RNAseq != false) {
                    adapterSeqR2   = Channel.value(params.adapterSeqR2RNAseq)
                    fastpAdapter += " --adapter_sequence_r2 " + adapterSeqR2.getVal()
                }
            }
        }

        if(single_end_RNA)
            """
            fastp --thread ${task.cpus} \\
                --in1 ${readsRNAseq_FWD} \\
                --out1 ${TumorReplicateId}_RNA_trimmed_R1.fastq.gz \\
                --json ${TumorReplicateId}_RNA_fastp.json \\
                ${fastpAdapter} \\
                ${params.fastpOpts}
            touch NO_FILE
            """
        else
            """
            fastp --thread ${task.cpus} \\
                --in1 ${readsRNAseq_FWD} \\
                --in2 ${readsRNAseq_REV} \\
                --out1 ${TumorReplicateId}_RNA_trimmed_R1.fastq.gz \\
                --out2 ${TumorReplicateId}_RNA_trimmed_R2.fastq.gz \\
                --json ${TumorReplicateId}_RNA_fastp.json \\
                ${fastpAdapter} \\
                ${params.fastpOpts}
            """
    }

    // FastQC after RNAseq adapter trimming
    process FastQC_trimmed_RNAseq {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "${params.outputDir}/analyses/$TumorReplicateId/QC/fastqc/",
            mode: params.publishDirMode,
            saveAs: { filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"}

        if (single_end_RNA) {
            cpus = 1
        } else {
            cpus = 2
        }

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(readsRNAseq_FWD),
            file(readsRNAseq_REV)
        ) from fastqc_readsRNAseq_trimmed_ch

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("*_fastqc*")
        ) into ch_fastqc_trimmed_RNAseq // multiQC

        script:
        if (single_end_RNA)
            """
            fastqc --quiet --threads ${task.cpus} ${readsRNAseq_FWD}
            """
        else
            """
            fastqc --quiet --threads ${task.cpus} \\
                ${readsRNAseq_FWD} ${readsRNAseq_REV}
            """
    }

} else { // no adapter trimming for RNAseq

    (
        reads_tumor_neofuse_ch,
        reads_tumor_optitype_ch,
        reads_tumor_hlahd_RNA_ch,
        reads_tumor_mixcr_RNA_ch,
        ch_fastp_RNAseq
    ) = raw_reads_tumor_neofuse_ch.into(5)

    ch_fastp_RNAseq = ch_fastp_RNAseq
                            .map{ it -> tuple(it[0], it[1], "")}

    (ch_fastqc_trimmed_RNAseq, ch_fastp_RNAseq) = ch_fastp_RNAseq.into(2)

}


// mix tumor normal channels and add sampleType (T/N) so that we can split again
reads_uBAM_ch = Channel.empty()
                        .mix(
                            reads_tumor_uBAM_ch
                                .combine(Channel.of("T")),
                            reads_normal_uBAM_ch
                                .combine(Channel.of("N"))
                        )


/////// start processing reads ///////

// make uBAM
process 'make_uBAM' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/01_preprocessing/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(readsFWD),
        file(readsREV),
        sampleType
    ) from reads_uBAM_ch


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(outFileName)
    ) into uBAM_out_ch0

    script:
    outFileName = (sampleType == "T") ? TumorReplicateId + "_unaligned.bam" : NormalReplicateId + "_unaligned.bam"
    procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId
    java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'

    if (single_end)
        """
        mkdir -p ${tmpDir}
        gatk --java-options ${java_opts} FastqToSam \\
            --TMP_DIR ${tmpDir} \\
            --MAX_RECORDS_IN_RAM ${params.maxRecordsInRam} \\
            -F1 ${readsFWD} \\
            --READ_GROUP_NAME ${procSampleName} \\
            --SAMPLE_NAME ${procSampleName} \\
            --LIBRARY_NAME ${procSampleName} \\
            --PLATFORM ILLUMINA \\
            -O ${procSampleName}_unaligned.bam
        """
    else
        """
        mkdir -p ${tmpDir}
        gatk --java-options ${java_opts} FastqToSam \\
            --TMP_DIR ${tmpDir} \\
            --MAX_RECORDS_IN_RAM ${params.maxRecordsInRam} \\
            -F1 ${readsFWD} \\
            -F2 ${readsREV} \\
            --READ_GROUP_NAME ${procSampleName} \\
            --SAMPLE_NAME ${procSampleName} \\
            --LIBRARY_NAME ${procSampleName} \\
            --PLATFORM ILLUMINA \\
            -O ${procSampleName}_unaligned.bam
        """
}

reads_ch = Channel.empty()
                    .mix(
                        reads_tumor_ch
                            .combine(Channel.of("T")),
                        reads_normal_ch
                            .combine(Channel.of("N"))
                    )


// Aligning reads to reference, sort and index; create BAMs
process 'Bwa' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/02_alignments/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(readsFWD),
        file(readsREV),
        sampleType
    ) from reads_ch
    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict),
        file(BwaRef)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict,
          reference.BwaRef ]
    )

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(outFileName)
    ) into Bwa_out_ch0

    script:
    outFileName = (sampleType == "T") ? TumorReplicateId + "_aligned.bam" : NormalReplicateId + "_aligned.bam"
    procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId

    sort_threads = (task.cpus.compareTo(8) == 1) ? 8 : task.cpus
    read_files = (single_end) ? readsFWD : readsFWD + " " + readsREV
    """
    bwa mem \\
        -R "@RG\\tID:${procSampleName}\\tLB:${procSampleName}\\tSM:${procSampleName}\\tPL:ILLUMINA" \\
        -M ${RefFasta} \\
        -t ${task.cpus} \\
        -Y \\
        ${read_files} | \\
    samtools view -@2 -Shbu - | \\
    sambamba sort \\
        --sort-picard \\
        --tmpdir=${tmpDir} \\
        -m ${params.SB_sort_mem} \\
        -l 6 \\
        -t ${sort_threads} \\
        -o ${outFileName} \\
        /dev/stdin
    """
}


// merge alinged BAM and uBAM
process 'merge_uBAM_BAM' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/02_alignments/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(BAM),
        file(uBAM)
    ) from Bwa_out_ch0
        .combine(uBAM_out_ch0, by: [0,1,2])

    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict),
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file("${procSampleName}_aligned_uBAM_merged.bam")
    ) into uBAM_BAM_out_ch

    script:
    procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId

    paired_run = (single_end) ? 'false' : 'true'
    java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'
    """
    mkdir -p ${tmpDir}

    gatk --java-options ${java_opts} MergeBamAlignment \\
        --TMP_DIR ${tmpDir} \\
        --VALIDATION_STRINGENCY SILENT \\
        --EXPECTED_ORIENTATIONS FR \\
        --ATTRIBUTES_TO_RETAIN X0 \\
        --REFERENCE_SEQUENCE ${RefFasta} \\
        --PAIRED_RUN ${paired_run} \\
        --SORT_ORDER "queryname" \\
        --IS_BISULFITE_SEQUENCE false \\
        --ALIGNED_READS_ONLY false \\
        --CLIP_ADAPTERS false \\
        --MAX_RECORDS_IN_RAM ${params.maxRecordsInRamMerge} \\
        --ADD_MATE_CIGAR true \\
        --MAX_INSERTIONS_OR_DELETIONS -1 \\
        --PRIMARY_ALIGNMENT_STRATEGY MostDistant \\
        --UNMAPPED_READ_STRATEGY COPY_TO_TAG \\
        --ALIGNER_PROPER_PAIR_FLAGS true \\
        --UNMAP_CONTAMINANT_READS true \\
        --ALIGNED_BAM ${BAM} \\
        --UNMAPPED_BAM ${uBAM} \\
        --OUTPUT ${procSampleName}_aligned_uBAM_merged.bam
    """
}


// Mark duplicates with sambamba
process 'MarkDuplicates' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/02_alignments/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(bam)
    ) from uBAM_BAM_out_ch // BwaTumor_out_ch0

    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file("${procSampleName}_aligned_sort_mkdp.bam"),
        file("${procSampleName}_aligned_sort_mkdp.bai")
    ) into (
        MarkDuplicates_out_ch0,
        MarkDuplicates_out_ch1,
        MarkDuplicates_out_ch2,
        MarkDuplicates_out_ch3,
        MarkDuplicates_out_ch4
    )

    script:
    procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId

    """
    mkdir -p ${tmpDir}
    sambamba markdup \\
        -t ${task.cpus} \\
        --tmpdir ${tmpDir} \\
        --hash-table-size=${params.SB_hash_table_size } \\
        --overflow-list-size=${params.SB_overflow_list_size} \\
        --io-buffer-size=${params.SB_io_buffer_size} \\
        ${bam} \\
        /dev/stdout | \\
    samtools sort \\
        -@${task.cpus} \\
        -m ${params.STperThreadMem} \\
        -O BAM \\
        -l 0 \\
        /dev/stdin | \\
    gatk --java-options ${params.JAVA_Xmx} SetNmMdAndUqTags \\
        --TMP_DIR ${tmpDir} \\
        -R ${RefFasta} \\
        -I /dev/stdin \\
        -O ${procSampleName}_aligned_sort_mkdp.bam \\
        --CREATE_INDEX true \\
        --MAX_RECORDS_IN_RAM ${params.maxRecordsInRam} \\
        --VALIDATION_STRINGENCY LENIENT

    """
}

// prepare channel for mhc_extract -> hld-hd, optitype
MarkDuplicatesTumor_out_ch0 = MarkDuplicates_out_ch3
                                .filter {
                                    it[2] == "T"
                                }
MarkDuplicatesTumor_out_ch0 = MarkDuplicatesTumor_out_ch0
                                .map{
                                        TumorReplicateId,
                                        NormalReplicateId,
                                        sampleType,
                                        TumorBAM,
                                        TumorBAI  -> tuple(
                                            TumorReplicateId,
                                            NormalReplicateId,
                                            TumorBAM,
                                            TumorBAI
                                        )
                                    }


MarkDuplicatesTumor = Channel.create()
MarkDuplicatesNormal = Channel.create()

MarkDuplicates_out_ch4
    .choice(
        MarkDuplicatesTumor, MarkDuplicatesNormal
    ) { it[2] == "T" ? 0 : 1 }

MarkDuplicates_out_CNVkit_ch0 = MarkDuplicatesTumor.combine(MarkDuplicatesNormal, by: [0,1])
MarkDuplicates_out_CNVkit_ch0 = MarkDuplicates_out_CNVkit_ch0
    .map{ TumorReplicateId, NormalReplicateId,
          sampleTypeT, recalTumorBAM, recalTumorBAI,
          sampleTypeN, recalNormalBAM, recalNormalBAI -> tuple(
          TumorReplicateId, NormalReplicateId,
          recalTumorBAM, recalTumorBAI,
          recalNormalBAM, recalNormalBAI
        )}

if(params.WES) {
    // Generate HS metrics using picard
    process 'alignmentMetrics' {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/QC/alignments/",
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            sampleType,
            file(bam),
            file(bai)
        ) from MarkDuplicates_out_ch0

        set(
            file(RefFasta),
            file(RefIdx)
        ) from Channel.value(
            [ reference.RefFasta,
            reference.RefIdx ]
        )

        file(BaitIntervalsList) from BaitsBedToIntervalList_out_ch0
        file(IntervalsList) from RegionsBedToIntervalList_out_ch1


        output:
        set(TumorReplicateId,
            NormalReplicateId,
            sampleType,
            file("${procSampleName}.*.txt")
        ) into alignmentMetrics_ch // multiQC

        script:
        procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId
        java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'

        """
        mkdir -p ${tmpDir}
        gatk --java-options ${java_opts} CollectHsMetrics \\
            --TMP_DIR ${tmpDir} \\
            --INPUT ${bam} \\
            --OUTPUT ${procSampleName}.HS.metrics.txt \\
            -R ${RefFasta} \\
            --BAIT_INTERVALS ${BaitIntervalsList} \\
            --TARGET_INTERVALS ${IntervalsList} \\
            --PER_TARGET_COVERAGE ${procSampleName}.perTarget.coverage.txt && \\
        gatk --java-options ${java_opts} CollectAlignmentSummaryMetrics \\
            --TMP_DIR ${tmpDir} \\
            --INPUT ${bam} \\
            --OUTPUT ${procSampleName}.AS.metrics.txt \\
            -R ${RefFasta} &&
        samtools flagstat -@${task.cpus} ${bam} > ${procSampleName}.flagstat.txt
        """
    }

    alignmentMetricsTumor_ch = Channel.create()
    alignmentMetricsNormal_ch = Channel.create()

    alignmentMetrics_ch
        .choice(
            alignmentMetricsTumor_ch, alignmentMetricsNormal_ch
        ) { it[2] == "T" ? 0 : 1 }

    alignmentMetricsTumor_ch = alignmentMetricsTumor_ch
            .map{
                    TumorReplicateId, NormalReplicateId,
                    sampleTypeN, metricFiles -> tuple(
                        TumorReplicateId,
                        NormalReplicateId,
                        metricFiles
                    )
                }

    alignmentMetricsNormal_ch = alignmentMetricsNormal_ch
            .map{
                    TumorReplicateId, NormalReplicateId,
                    sampleTypeN, metricFiles -> tuple(
                        TumorReplicateId,
                        NormalReplicateId,
                        metricFiles
                    )
                }

} else {
    // bogus channel for multiqc
    alignmentMetricsTumor_ch = MarkDuplicates_out_ch0
                            .map{ it -> tuple(it[0],it[1], "")}
    (alignmentMetricsNormal_ch, alignmentMetricsTumor_ch) = alignmentMetricsTumor_ch.into(2)
}


/*
 BaseRecalibrator (GATK4): generates recalibration table for Base Quality Score
 Recalibration (BQSR)
 ApplyBQSR (GATK4): apply BQSR table to reads
*/
process 'scatterBaseRecalGATK4' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(bam),
        file(bai),
        file(intervals)
    ) from MarkDuplicates_out_ch1
        .combine(
            SplitIntervals_out_scatterBaseRecalTumorGATK4_ch.flatten()
        )

    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    set(
        file(MillsGold),
        file(MillsGoldIdx),
        file(DBSNP),
        file(DBSNPIdx),
        file(KnownIndels),
        file(KnownIndelsIdx)
    ) from Channel.value(
        [ database.MillsGold,
          database.MillsGoldIdx,
          database.DBSNP,
          database.DBSNPIdx,
          database.KnownIndels,
          database.KnownIndelsIdx ]
    )


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file("${procSampleName}_${intervals}_bqsr.table")
    ) into scatterBaseRecalGATK4_out_ch0


    script:
    procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId

    """
    mkdir -p ${tmpDir}
    gatk  --java-options ${params.JAVA_Xmx} BaseRecalibrator \\
        --tmp-dir ${tmpDir} \\
        -I ${bam} \\
        -R ${RefFasta} \\
        -L ${intervals} \\
        -O ${procSampleName}_${intervals}_bqsr.table \\
        --known-sites ${DBSNP} \\
        --known-sites ${KnownIndels} \\
        --known-sites ${MillsGold}
    """
}

// gather scattered bqsr tables
process 'gatherGATK4scsatteredBQSRtables' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/$TumorReplicateId/03_baserecalibration/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(bqsr_table)
    ) from scatterBaseRecalGATK4_out_ch0
        .groupTuple(by: [0, 1, 2])


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file("${procSampleName}_bqsr.table")
    ) into gatherBQSRtables_out_ch0


    script:
    procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId
    """
    mkdir -p ${tmpDir}

    gatk GatherBQSRReports \\
        -I ${bqsr_table.join(" -I ")} \\
        -O ${procSampleName}_bqsr.table
    """
}


// ApplyBQSR (GATK4): apply BQSR table to reads
process 'scatterGATK4applyBQSRS' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(bam),
        file(bai),
        file(bqsr_table),
        file(intervals)
    ) from MarkDuplicates_out_ch2
        .combine(gatherBQSRtables_out_ch0, by: [0, 1, 2])
        .combine(
            SplitIntervals_out_scatterTumorGATK4applyBQSRS_ch.flatten()  // TODO: change channel name here and above
        )

    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    set(
        file(MillsGold),
        file(MillsGoldIdx),
        file(DBSNP),
        file(DBSNPIdx),
        file(KnownIndels),
        file(KnownIndelsIdx)
    ) from Channel.value(
        [ database.MillsGold,
          database.MillsGoldIdx,
          database.DBSNP,
          database.DBSNPIdx,
          database.KnownIndels,
          database.KnownIndelsIdx ]
    )


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file("${procSampleName}_${intervals}_recal4.bam"),
        file("${procSampleName}_${intervals}_recal4.bai")
    ) into scatterGATK4applyBQSRS_out_GatherRecalBamFiles_ch0


    script:
    procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId
    """
    mkdir -p ${tmpDir}
    gatk ApplyBQSR \\
        --java-options ${params.JAVA_Xmx} \\
        --tmp-dir ${tmpDir} \\
        -I ${bam} \\
        -R ${RefFasta} \\
        -L ${intervals} \\
        -O ${procSampleName}_${intervals}_recal4.bam \\
        --bqsr-recal-file ${bqsr_table}
    """
}

process 'GatherRecalBamFiles' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/03_baserecalibration/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(bam),
        file(bai)
    ) from scatterGATK4applyBQSRS_out_GatherRecalBamFiles_ch0
        .toSortedList({a, b -> a[3].baseName <=> b[3].baseName})
        .flatten()
        .collate(5)
        .groupTuple(by: [0, 1, 2])

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file("${procSampleName}_recalibrated.bam"),
        file("${procSampleName}_recalibrated.bam.bai")
    ) into (
        BaseRecalGATK4_out_ch0,
        BaseRecalGATK4_out_ch1,
        BaseRecalGATK4_out_ch2, // into mutect2
        GatherRecalBamFiles_out_IndelRealignerIntervals_ch0
    )

    script:
    procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId
    java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'
    """
    mkdir -p ${tmpDir}

    rm -f ${procSampleName}_gather.fifo
    mkfifo ${procSampleName}_gather.fifo
    gatk --java-options ${java_opts} GatherBamFiles \\
        --TMP_DIR ${tmpDir} \\
        -I ${bam.join(" -I ")} \\
        -O ${procSampleName}_gather.fifo \\
        --CREATE_INDEX false \\
        --MAX_RECORDS_IN_RAM ${params.maxRecordsInRam} &
    samtools sort \\
        -@${task.cpus} \\
        -m ${params.STperThreadMem} \\
        -o ${procSampleName}_recalibrated.bam ${procSampleName}_gather.fifo
    samtools index -@${task.cpus} ${procSampleName}_recalibrated.bam
    rm -f ${procSampleName}_gather.fifo
    """
}


// GetPileupSummaries (GATK4): tabulates pileup metrics for inferring contamination
process 'GetPileup' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/mutect2/processing/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        file(GnomAD),
        file(GnomADIdx)
    ) from Channel.value(
        [ database.GnomAD,
          database.GnomADIdx ]
    )

    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(bam),
        file(bai),
        file(IntervalsList)
    ) from BaseRecalGATK4_out_ch0
        .combine(
            preprocessIntervalList_out_ch3
        )

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file("${procSampleName}_pileup.table")
    ) into GetPileup_out_ch0

    script:
    procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId
    """
    mkdir -p ${tmpDir}

    gatk GetPileupSummaries \\
        --tmp-dir ${tmpDir} \\
        -I ${bam} \\
        -O ${procSampleName}_pileup.table \\
        -L ${IntervalsList} \\
        --variant ${GnomAD}
    """
}


BaseRecalTumor = Channel.create()
BaseRecalNormal = Channel.create()

BaseRecalGATK4_out_ch2
    .choice(
        BaseRecalTumor, BaseRecalNormal
    ) { it[2] == "T" ? 0 : 1 }

(BaseRecalNormal_out_ch0, BaseRecalNormal) = BaseRecalNormal.into(2)
BaseRecalNormal_out_ch0 = BaseRecalNormal_out_ch0
        .map{ TumorReplicateId, NormalReplicateId,
            sampleTypeN, recalNormalBAM, recalNormalBAI -> tuple(
            TumorReplicateId, NormalReplicateId,
            recalNormalBAM, recalNormalBAI
            )}


BaseRecalGATK4_out = BaseRecalTumor.combine(BaseRecalNormal, by: [0,1])
BaseRecalGATK4_out = BaseRecalGATK4_out
    .map{ TumorReplicateId, NormalReplicateId,
          sampleTypeT, recalTumorBAM, recalTumorBAI,
          sampleTypeN, recalNormalBAM, recalNormalBAI -> tuple(
          TumorReplicateId, NormalReplicateId,
          recalTumorBAM, recalTumorBAI,
          recalNormalBAM, recalNormalBAI
        )}

if (have_GATK3) {
    (
        BaseRecalGATK4_out_Mutect2_ch0,
        BaseRecalGATK4_out_MantaSomaticIndels_ch0,
        BaseRecalGATK4_out_StrelkaSomatic_ch0,
        BaseRecalGATK4_out_MutationalBurden_ch0,
        BaseRecalGATK4_out_MutationalBurden_ch1
    ) = BaseRecalGATK4_out.into(5)
} else {
    (
        BaseRecalGATK4_out_Mutect2_ch0,
        BaseRecalGATK4_out_MantaSomaticIndels_ch0,
        BaseRecalGATK4_out_StrelkaSomatic_ch0,
        BaseRecalGATK4_out_MutationalBurden_ch0,
        BaseRecalGATK4_out_MutationalBurden_ch1,
        BaseRecalGATK4_out
    ) = BaseRecalGATK4_out.into(6)
}

/*
    MUTECT2
    Call somatic SNPs and indels via local re-assembly of haplotypes; tumor sample
    and matched normal sample
*/
process 'Mutect2' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/mutect2/processing/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict),
        file(gnomADfull),
        file(gnomADfullIdx)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict,
          database.GnomADfull,
          database.GnomADfullIdx ]
    )
    file pon from pon_file

    set(
        TumorReplicateId,
        NormalReplicateId,
        file(Tumorbam),
        file(Tumorbai),
        file(Normalbam),
        file(Normalbai),
        file(intervals)
    ) from BaseRecalGATK4_out_Mutect2_ch0
        .combine(
            SplitIntervals_out_ch2.flatten()
        )

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${intervals}.vcf.gz"),
        file("${TumorReplicateId}_${intervals}.vcf.gz.stats"),
        file("${TumorReplicateId}_${intervals}.vcf.gz.tbi"),
        file("${TumorReplicateId}_${intervals}-f1r2.tar.gz")
    ) into Mutect2_out_ch0


    script:
    def panel_of_normals = (pon.name != 'NO_FILE') ? "--panel-of-normals $pon" : ""
    def mk_pon_idx = (pon.name != 'NO_FILE') ? "tabix -f $pon" : ""
    """
    mkdir -p ${tmpDir}

    ${mk_pon_idx}

    gatk Mutect2 \\
        --tmp-dir ${tmpDir} \\
        -R ${RefFasta} \\
        -I ${Tumorbam} -tumor ${TumorReplicateId} \\
        -I ${Normalbam} -normal ${NormalReplicateId} \\
        --germline-resource ${gnomADfull} \\
        ${panel_of_normals} \\
        -L ${intervals} \\
        --native-pair-hmm-threads ${task.cpus} \\
        --f1r2-tar-gz ${TumorReplicateId}_${intervals}-f1r2.tar.gz \\
        -O ${TumorReplicateId}_${intervals}.vcf.gz
    """
}

// Merge scattered Mutect2 vcfs
process 'gatherMutect2VCFs' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/mutect2/",
        mode: params.publishDirMode,
        saveAs: {
            filename ->
                if(filename.indexOf("_read-orientation-model.tar.gz") > 0 && params.fullOutput) {
                    return "processing/$filename"
                } else if(filename.indexOf("_read-orientation-model.tar.gz") > 0 && ! params.fullOutput) {
                    return null
                } else {
                    return "raw/$filename"
                }
        }


    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(vcf),
        file(stats),
        file(idx),
        file(f1r2_tar_gz)
    ) from Mutect2_out_ch0
        .groupTuple(by: [0, 1])


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_mutect2_raw.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_mutect2_raw.vcf.gz.tbi"),
        file("${TumorReplicateId}_${NormalReplicateId}_mutect2_raw.vcf.gz.stats"),
        file("${TumorReplicateId}_${NormalReplicateId}_read-orientation-model.tar.gz")
    ) into gatherMutect2VCFs_out_ch0

    script:
    java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'
    """
    mkdir -p ${tmpDir}

    gatk --java-options ${java_opts} MergeVcfs \\
        --TMP_DIR ${tmpDir} \\
        -I ${vcf.join(" -I ")} \\
        -O ${TumorReplicateId}_${NormalReplicateId}_mutect2_raw.vcf.gz

    gatk MergeMutectStats \\
        --tmp-dir ${tmpDir} \\
        --stats ${stats.join(" --stats ")} \\
        -O ${TumorReplicateId}_${NormalReplicateId}_mutect2_raw.vcf.gz.stats

    gatk LearnReadOrientationModel \\
        --tmp-dir ${tmpDir} \\
        -I ${f1r2_tar_gz.join(" -I ")} \\
        -O ${TumorReplicateId}_${NormalReplicateId}_read-orientation-model.tar.gz
    """
}


PileupTumor = Channel.create()
PileupNormal = Channel.create()

GetPileup_out_ch0
    .choice(
        PileupTumor, PileupNormal
    ) { it[2] == "T" ? 0 : 1 }

GetPileup_out = PileupTumor.combine(PileupNormal, by: [0,1])
GetPileup_out = GetPileup_out
    .map{ TumorReplicateId, NormalReplicateId, sampleTypeT, pileupTumor, sampleTypeN, pileupNormal -> tuple(
            TumorReplicateId, NormalReplicateId, pileupTumor, pileupNormal
        )}



/*
CalculateContamination (GATK4): calculate fraction of reads coming from
cross-sample contamination
FilterMutectCalls (GATK4): filter somatic SNVs and indels
FilterByOrientationBias (GATK4): filter variant calls using orientation bias
SelectVariants (GATK4): select subset of variants from a larger callset
VariantFiltration (GATK4): filter calls based on INFO and FORMAT annotations
*/
process 'FilterMutect2' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/mutect2/",
        mode: params.publishDirMode

    input:
    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    set(
        TumorReplicateId,
        NormalReplicateId,
        file(pileupTumor),
        file(pileupNormal),
        file(vcf),
        file(vcfIdx),
        file(vcfStats),
        file(f1r2_tar_gz)
    ) from GetPileup_out
        .combine(gatherMutect2VCFs_out_ch0, by :[0,1])

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        val("mutect2"),
        file("${TumorReplicateId}_${NormalReplicateId}_mutect2_final.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_mutect2_final.vcf.gz.tbi")
    ) into (
        FilterMutect2_out_ch0,
        FilterMutect2_out_ch1
    )

    script:
    """
    mkdir -p ${tmpDir}

    gatk CalculateContamination \\
        --tmp-dir ${tmpDir} \\
        -I ${pileupTumor} \\
        --matched-normal ${pileupNormal} \\
        -O ${TumorReplicateId}_${NormalReplicateId}_cont.table && \\
    gatk FilterMutectCalls \\
        --tmp-dir ${tmpDir} \\
        -R ${RefFasta} \\
        -V ${vcf} \\
        --contamination-table ${TumorReplicateId}_${NormalReplicateId}_cont.table \\
        --ob-priors ${f1r2_tar_gz} \\
        -O ${TumorReplicateId}_${NormalReplicateId}_oncefiltered.vcf.gz && \\
    gatk SelectVariants \\
        --tmp-dir ${tmpDir} \\
        --variant ${TumorReplicateId}_${NormalReplicateId}_oncefiltered.vcf.gz \\
        -R ${RefFasta} \\
        --exclude-filtered true \\
        --select 'vc.getGenotype(\"${TumorReplicateId}\").getAD().1 >= ${params.minAD}' \\
        --output ${TumorReplicateId}_${NormalReplicateId}_mutect2_final.vcf.gz
    """
}


// HaploTypeCaller
/*
    Call germline SNPs and indels via local re-assembly of haplotypes; normal sample
    germline variants are needed for generating phased vcfs for pVACtools
*/
process 'HaploTypeCaller' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/haplotypecaller/processing/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict),
        file(DBSNP),
        file(DBSNPIdx)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict,
          database.DBSNP,
          database.DBSNPIdx ]
    )

    set(
        TumorReplicateId,
        NormalReplicateId,
        file(Normalbam),
        file(Normalbai),
        file(intervals)
    ) from BaseRecalNormal_out_ch0
        .combine(
            SplitIntervals_out_ch5.flatten()
        )

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${NormalReplicateId}_germline_${intervals}.vcf.gz"),
        file("${NormalReplicateId}_germline_${intervals}.vcf.gz.tbi"),
        file(Normalbam),
        file(Normalbai)
    ) into (
        HaploTypeCaller_out_ch0
    )


    script:
    """
    mkdir -p ${tmpDir}

    gatk --java-options ${params.JAVA_Xmx} HaplotypeCaller \\
        --tmp-dir ${tmpDir} \\
        -R ${RefFasta} \\
        -I ${Normalbam} \\
        -L ${intervals} \\
        --native-pair-hmm-threads ${task.cpus} \\
        --dbsnp ${DBSNP} \\
        -O ${NormalReplicateId}_germline_${intervals}.vcf.gz
    """
}


/*
    Run a Convolutional Neural Net to filter annotated germline variants; normal sample
    germline variants are needed for generating phased vcfs for pVACtools
*/
process 'CNNScoreVariants' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/haplotypecaller/processing/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    set(
        TumorReplicateId,
        NormalReplicateId,
        file(raw_germline_vcf),
        file(raw_germline_vcf_tbi),
        file(Normalbam),
        file(Normalbai)
    ) from HaploTypeCaller_out_ch0

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${raw_germline_vcf.baseName}_CNNScored.vcf.gz"),
        file("${raw_germline_vcf.baseName}_CNNScored.vcf.gz.tbi")
    ) into CNNScoreVariants_out_ch0


    script:
    """
    mkdir -p ${tmpDir}

    gatk CNNScoreVariants \\
        --tmp-dir ${tmpDir} \\
        -R ${RefFasta} \\
        -I ${Normalbam} \\
        -V ${raw_germline_vcf} \\
        -tensor-type read_tensor \\
        --inter-op-threads ${task.cpus} \\
        --intra-op-threads ${task.cpus} \\
        --transfer-batch-size ${params.transferBatchSize} \\
        --inference-batch-size ${params.inferenceBatchSize} \\
        -O ${raw_germline_vcf.baseName}_CNNScored.vcf.gz
    """
}


// Merge scattered filtered germline vcfs
process 'MergeHaploTypeCallerGermlineVCF' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/haplotypecaller/raw/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(filtered_germline_vcf),
        file(filtered_germline_vcf_tbi)
    ) from CNNScoreVariants_out_ch0
        .groupTuple(by: [0, 1])

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${NormalReplicateId}_germline_CNNscored.vcf.gz"),
        file("${NormalReplicateId}_germline_CNNscored.vcf.gz.tbi"),
    ) into MergeHaploTypeCallerGermlineVCF_out_ch0

    script:
    java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'
    """
    mkdir -p ${tmpDir}

    gatk --java-options ${java_opts} MergeVcfs \\
        --TMP_DIR ${tmpDir} \\
        -I ${filtered_germline_vcf.join(" -I ")} \\
        -O ${NormalReplicateId}_germline_CNNscored.vcf.gz
    """
}

/*
    Apply a Convolutional Neural Net to filter annotated germline variants; normal sample
    germline variants are needed for generating phased vcfs for pVACtools
*/
process 'FilterGermlineVariantTranches' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/haplotypecaller/",
        mode: params.publishDirMode

    input:
    set(
        file(MillsGold),
        file(MillsGoldIdx),
        file(HapMap),
        file(HapMapIdx),
        file(hcSNPS1000G),
        file(hcSNPS1000GIdx)
    ) from Channel.value(
        [ database.MillsGold,
          database.MillsGoldIdx,
          database.HapMap,
          database.HapMapIdx,
          database.hcSNPS1000G,
          database.hcSNPS1000GIdx ]
    )

    set(
        TumorReplicateId,
        NormalReplicateId,
        file(scored_germline_vcf),
        file(scored_germline_vcf_tbi)
    ) from MergeHaploTypeCallerGermlineVCF_out_ch0

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${scored_germline_vcf.simpleName}_Filtered.vcf.gz"),
        file("${scored_germline_vcf.simpleName}_Filtered.vcf.gz.tbi")
    ) into FilterGermlineVariantTranches_out_ch0


    script:
    """
    mkdir -p ${tmpDir}

    gatk FilterVariantTranches \\
        --tmp-dir ${tmpDir} \\
        -V ${scored_germline_vcf} \\
        --resource ${hcSNPS1000G} \\
        --resource ${HapMap} \\
        --resource ${MillsGold} \\
        --info-key CNN_2D \\
        --snp-tranche 99.95 \\
        --indel-tranche 99.4 \\
        --invalidate-previous-filters \\
        -O ${scored_germline_vcf.simpleName}_Filtered.vcf.gz
    """
}


// END HTC


/*
 RealignerTargetCreator (GATK3): define intervals to target for local realignment
 IndelRealigner (GATK3): perform local realignment of reads around indels
*/
if (have_GATK3) {
    process 'IndelRealignerIntervals' {

        label 'GATK3'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/03_realignment/processing/",
            mode: params.publishDirMode,
            enabled: params.fullOutput

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            sampleType,
            file(bam),
            file(bai)
        ) from GatherRecalBamFiles_out_IndelRealignerIntervals_ch0

        set(
            file(RefFasta),
            file(RefIdx),
            file(RefDict)
        ) from Channel.value(
            [ reference.RefFasta,
            reference.RefIdx,
            reference.RefDict ]
        )

        set(
            file(KnownIndels),
            file(KnownIndelsIdx),
            file(MillsGold),
            file(MillsGoldIdx)
        ) from Channel.value(
            [ database.KnownIndels,
            database.KnownIndelsIdx,
            database.MillsGold,
            database.MillsGoldIdx ]
        )

        each file(interval) from SplitIntervals_out_ch3.flatten()

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            sampleType,
            file("${procSampleName}_recalibrated_realign_${interval}.bam"),
            file("${procSampleName}_recalibrated_realign_${interval}.bai")
        ) into IndelRealignerIntervals_out_GatherRealignedBamFiles_ch0

        script:
        procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId
        """
        mkdir -p ${tmpDir}

        $JAVA8 ${params.JAVA_Xmx} -XX:ParallelGCThreads=${task.cpus} -Djava.io.tmpdir=${tmpDir} -jar $GATK3 \\
            -T RealignerTargetCreator \\
            --known ${MillsGold} \\
            --known ${KnownIndels} \\
            -R ${RefFasta} \\
            -L ${interval} \\
            -I ${bam} \\
            -o ${interval}_target.list \\
            -nt ${task.cpus} && \\
        $JAVA8 -XX:ParallelGCThreads=${task.cpus} -Djava.io.tmpdir=${tmpDir} -jar $GATK3 \\
            -T IndelRealigner \\
            -R ${RefFasta} \\
            -L ${interval} \\
            -I ${bam} \\
            -targetIntervals ${interval}_target.list \\
            -known ${KnownIndels} \\
            -known ${MillsGold} \\
            -nWayOut _realign_${interval}.bam && \\
        rm ${interval}_target.list
        """
    }

    process 'GatherRealignedBamFiles' {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/03_realignment/",
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            sampleType,
            file(bam),
            file(bai)
        ) from IndelRealignerIntervals_out_GatherRealignedBamFiles_ch0
            .toSortedList({a, b -> a[3].baseName <=> b[3].baseName})
            .flatten()
            .collate(5)
            .groupTuple(by: [0,1,2])

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            sampleType,
            file("${procSampleName}_recalibrated_realign.bam"),
            file("${procSampleName}_recalibrated_realign.bam.bai")
        ) into GatherRealignedBamFiles_out_ch

        script:
        procSampleName = (sampleType == "T") ? TumorReplicateId : NormalReplicateId
        java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'
        """
        mkdir -p ${tmpDir}

        rm -f ${procSampleName}_gather.fifo
        mkfifo ${procSampleName}_gather.fifo
        gatk --java-options ${java_opts} GatherBamFiles \\
            --TMP_DIR ${tmpDir} \\
            -I ${bam.join(" -I ")} \\
            -O ${procSampleName}_gather.fifo \\
            --CREATE_INDEX false \\
            --MAX_RECORDS_IN_RAM ${params.maxRecordsInRam} &
        samtools sort \\
            -@${task.cpus} \\
            -m ${params.STperThreadMem} \\
            -o ${procSampleName}_recalibrated_realign.bam ${procSampleName}_gather.fifo
        samtools index -@${task.cpus}  ${procSampleName}_recalibrated_realign.bam
        rm -f ${procSampleName}_gather.fifo
        """
    }

    recalRealTumor = Channel.create()
    recalRealNormal = Channel.create()

    (
        GatherRealignedBamFiles_out_AlleleCounter_ch0,
        GatherRealignedBamFiles_out_Mpileup4ControFREEC_ch0,
        GatherRealignedBamFiles_out_ch
    ) = GatherRealignedBamFiles_out_ch.into(3)

    GatherRealignedBamFiles_out_ch
        .choice(
            recalRealTumor, recalRealNormal
        ) { it[2] == "T" ? 0 : 1 }


    (
        recalRealTumor_tmp,
        recalRealTumor
    ) = recalRealTumor.into(2)

    recalRealTumor_tmp = recalRealTumor_tmp
                            .map{ TumorReplicateId, NormalReplicateId,
                                    sampleTypeT, realTumorBAM, realTumorBAI -> tuple(
                                        TumorReplicateId, NormalReplicateId,
                                        realTumorBAM, realTumorBAI
                                    )
                                }

    (
        GatherRealignedBamFilesTumor_out_FilterVarscan_ch0,
        GatherRealignedBamFilesTumor_out_mkPhasedVCF_ch0
    ) = recalRealTumor_tmp.into(2)


    RealignedBamFiles = recalRealTumor.combine(recalRealNormal, by: [0,1])
    RealignedBamFiles = RealignedBamFiles
                        .map{ TumorReplicateId, NormalReplicateId,
                                sampleTypeT, realTumorBAM, realTumorBAI,
                                sampleTypeN, realNormalBAM, realNormalBAI -> tuple(
                                    TumorReplicateId, NormalReplicateId,
                                    realTumorBAM, realTumorBAI,
                                    realNormalBAM, realNormalBAI
                                )
                            }
    (
        VarscanBAMfiles_ch, // GatherRealignedBamFiles_out_VarscanSomaticScattered_ch0,
        GatherRealignedBamFiles_out_Mutect1scattered_ch0,
        GatherRealignedBamFiles_out_Sequenza_ch0
    ) = RealignedBamFiles.into(3)

} else {

    log.info "INFO: GATK3 not installed! Can not generate indel realigned BAMs for varscan and mutect1\n"

    (
        VarscanBAMfiles_ch,
        GatherRealignedBamFiles_out_Mutect1scattered_ch0,
        GatherRealignedBamFiles_out_Sequenza_ch0,
        BaseRecalGATK4_out
    ) = BaseRecalGATK4_out.into(4)

    GatherRealignedBamFilesTumor_out_FilterVarscan_ch0 = BaseRecalGATK4_out
                                                            .map{ TumorReplicateId, NormalReplicateId,
                                                                  recalTumorBAM, recalTumorBAI,
                                                                  recalNormalBAM, recalNormalBAI -> tuple(
                                                                      TumorReplicateId, NormalReplicateId,
                                                                      recalTumorBAM, recalTumorBAI
                                                                  )
                                                            }
    GatherRealignedBamFiles_out_AlleleCounter_ch0 = GatherRecalBamFiles_out_IndelRealignerIntervals_ch0

} // END if have GATK3

process 'VarscanSomaticScattered' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/varscan/processing/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(Tumorbam),
        file(Tumorbai),
        file(Normalbam),
        file(Normalbai),
        file(intervals)
    ) from VarscanBAMfiles_ch // GatherRealignedBamFiles_out_VarscanSomaticScattered_ch0
        .combine(
            ScatteredIntervalListToBed_out_ch0.flatten()
        )

    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict),
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_${intervals}_varscan.snp.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_${intervals}_varscan.indel.vcf")
    ) into VarscanSomaticScattered_out_ch0

    script:
    // awk filters at the end needed, found at least one occurence of "W" in Ref field of
    // varscan vcf (? wtf). Non ACGT seems to cause MergeVCF (picard) crashing
    """
    rm -f ${TumorReplicateId}_${NormalReplicateId}_${intervals}_mpileup.fifo
    mkfifo ${TumorReplicateId}_${NormalReplicateId}_${intervals}_mpileup.fifo
    samtools mpileup \\
        -q 1 \\
        -f ${RefFasta} \\
        -l ${intervals} \\
        ${Normalbam} ${Tumorbam} > ${TumorReplicateId}_${NormalReplicateId}_${intervals}_mpileup.fifo &
    varscan ${params.JAVA_Xmx} somatic \\
        ${TumorReplicateId}_${NormalReplicateId}_${intervals}_mpileup.fifo \\
        ${TumorReplicateId}_${NormalReplicateId}_${intervals}_varscan_tmp \\
        --output-vcf 1 \\
        --mpileup 1 \\
        --min-coverage ${params.min_cov} \\
        --min-coverage-normal ${params.min_cov_normal} \\
        --min-coverage-tumor ${params.min_cov_tumor} \\
        --min-freq-for-hom ${params.min_freq_for_hom} \\
        --tumor-purity ${params.tumor_purity} \\
        --p-value ${params.somatic_pvalue} \\
        --somatic-p-value ${params.somatic_somaticpvalue} \\
        --strand-filter ${params.strand_filter} && \\
    rm -f ${TumorReplicateId}_${NormalReplicateId}_${intervals}_mpileup.fifo && \\
    awk '{OFS=FS="\t"} { if(\$0 !~ /^#/) { if (\$4 ~ /[ACGT]/) { print } } else { print } }' \\
        ${TumorReplicateId}_${NormalReplicateId}_${intervals}_varscan_tmp.snp.vcf \\
        > ${TumorReplicateId}_${NormalReplicateId}_${intervals}_varscan.snp.vcf && \\
    awk '{OFS=FS="\t"} { if(\$0 !~ /^#/) { if (\$4 ~ /[ACGT]+/) { print } } else { print } }' \\
        ${TumorReplicateId}_${NormalReplicateId}_${intervals}_varscan_tmp.indel.vcf \\
        > ${TumorReplicateId}_${NormalReplicateId}_${intervals}_varscan.indel.vcf

    rm -f ${TumorReplicateId}_${NormalReplicateId}_${intervals}_varscan_tmp.*
    """


}

// Merge scattered Varscan vcfs
process 'gatherVarscanVCFs' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/varscan/processing/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    set(
        TumorReplicateId,
        NormalReplicateId,
        file(snp_vcf),
        file(indel_vcf)
    ) from VarscanSomaticScattered_out_ch0
        .toSortedList({a, b -> a[2].baseName <=> b[2].baseName})
        .flatten()
        .collate(4)
        .groupTuple(by: [0,1])


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.snp.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.indel.vcf")
    ) into gatherVarscanVCFs_out_ch0

    script:
    java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'
    """
    mkdir -p ${tmpDir}

    gatk --java-options ${java_opts} MergeVcfs \\
        --TMP_DIR ${tmpDir} \\
        -I ${snp_vcf.join(" -I ")} \\
        -O ${TumorReplicateId}_${NormalReplicateId}_varscan.snp.vcf \\
        --SEQUENCE_DICTIONARY ${RefDict}

    gatk --java-options ${java_opts} MergeVcfs \\
        --TMP_DIR ${tmpDir} \\
        -I ${indel_vcf.join(" -I ")} \\
        -O ${TumorReplicateId}_${NormalReplicateId}_varscan.indel.vcf \\
        --SEQUENCE_DICTIONARY ${RefDict}

    """
}

// Filter variants by somatic status and confidences
process 'ProcessVarscan' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/varscan/raw/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(snp),
        file(indel)
    ) from gatherVarscanVCFs_out_ch0

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.snp.Somatic.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.snp.Somatic.hc.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.snp.LOH.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.snp.LOH.hc.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.snp.Germline.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.snp.Germline.hc.vcf")
    ) into ProcessVarscanSNP_out_ch0

    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.indel.Somatic.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.indel.Somatic.hc.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.indel.LOH.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.indel.LOH.hc.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.indel.Germline.vcf"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.indel.Germline.hc.vcf")
    ) into ProcessVarscanIndel_out_ch0

    script:
    """
    varscan ${params.JAVA_Xmx} processSomatic \\
        ${snp} \\
        --min-tumor-freq ${params.min_tumor_freq} \\
        --max-normal-freq ${params.max_normal_freq} \\
        --p-value ${params.processSomatic_pvalue} && \\
    varscan ${params.JAVA_Xmx} processSomatic \\
        ${indel} \\
        --min-tumor-freq ${params.min_tumor_freq} \\
        --max-normal-freq ${params.max_normal_freq} \\
        --p-value ${params.processSomatic_pvalue}
    """
}

/*
    AWK-script: calcualtes start-end position of variant
    Bamreadcount: generate metrics at single nucleotide positions for filtering
    fpfilter (Varscan): apply false-positive filter to variants
*/
process 'FilterVarscan' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/varscan/processing/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(bam),
        file(bai),
        file(snpSomatic),
        file(snpSomaticHc),
        file(snpLOH),
        file(snpLOHhc),
        file(snpGerm),
        file(snpGemHc),
        file(indelSomatic),
        file(indelSomaticHc),
        file(indelLOH),
        file(indelLOHhc),
        file(indelGerm),
        file(indelGemHc)
    ) from GatherRealignedBamFilesTumor_out_FilterVarscan_ch0
        .combine(ProcessVarscanSNP_out_ch0, by :[0,1])
        .combine(ProcessVarscanIndel_out_ch0, by :[0,1])

    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.snp.Somatic.hc.filtered.vcf")
    ) into FilterVarscanSnp_out_ch0

    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.indel.Somatic.hc.filtered.vcf")
    ) into FilterVarscanIndel_out_ch0

    script:
    """
    cat ${snpSomaticHc} | \\
    awk '{if (!/^#/) { x = length(\$5) - 1; print \$1,\$2,(\$2+x); }}' | \\
    bam-readcount \\
        -q${params.min_map_q} \\
        -b${params.min_base_q} \\
        -w1 \\
        -l /dev/stdin \\
        -f ${RefFasta} \\
        ${bam} | \\
    varscan ${params.JAVA_Xmx} fpfilter \\
        ${snpSomaticHc} \\
        /dev/stdin \\
        --output-file ${TumorReplicateId}_${NormalReplicateId}_varscan.snp.Somatic.hc.filtered.vcf && \\
    cat ${indelSomaticHc} | \\
    awk '{if (! /^#/) { x = length(\$5) - 1; print \$1,\$2,(\$2+x); }}' | \\
    bam-readcount \\
        -q${params.min_map_q} \\
        -b${params.min_base_q} \\
        -w1 \\
        -l /dev/stdin \\
        -f ${RefFasta} ${bam} | \\
    varscan ${params.JAVA_Xmx} fpfilter \\
        ${indelSomaticHc} \\
        /dev/stdin \\
        --output-file ${TumorReplicateId}_${NormalReplicateId}_varscan.indel.Somatic.hc.filtered.vcf
    """
}


/*
    1. Merge filtered SNPS and INDELs from VarScan
    2. Rename the sample names (TUMOR/NORMAL) from varscan vcfs to the real samplenames
*/
process 'MergeAndRenameSamplesInVarscanVCF' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/varscan/",
        mode: params.publishDirMode

    input:
    file(RefDict) from Channel.value(reference.RefDict)

    set(
        TumorReplicateId,
        NormalReplicateId,
        file(VarScanSNP_VCF),
        file(VarScanINDEL_VCF)
    ) from FilterVarscanSnp_out_ch0
        .combine(FilterVarscanIndel_out_ch0, by: [0, 1])

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        val("varscan"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.Somatic.hc.filtered.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_varscan.Somatic.hc.filtered.vcf.gz.tbi")
    ) into (
        MergeAndRenameSamplesInVarscanVCF_out_ch0,
        MergeAndRenameSamplesInVarscanVCF_out_ch1
    )

    script:
    java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'
    """
    mkdir -p ${tmpDir}

    bgzip -c ${VarScanSNP_VCF} > ${VarScanSNP_VCF}.gz
    tabix -p vcf ${VarScanSNP_VCF}.gz
    bgzip -c ${VarScanINDEL_VCF} > ${VarScanINDEL_VCF}.gz
    tabix -p vcf ${VarScanINDEL_VCF}.gz

    gatk --java-options ${java_opts} MergeVcfs \\
        --TMP_DIR ${tmpDir} \\
        -I ${VarScanSNP_VCF}.gz \\
        -I ${VarScanINDEL_VCF}.gz \\
        -O ${TumorReplicateId}_varscan_combined.vcf.gz \\
        --SEQUENCE_DICTIONARY ${RefDict}

    gatk --java-options ${java_opts} SortVcf \\
        --TMP_DIR ${tmpDir} \\
        -I ${TumorReplicateId}_varscan_combined.vcf.gz \\
        -O ${TumorReplicateId}_varscan_combined_sorted.vcf.gz \\
        --SEQUENCE_DICTIONARY ${RefDict}

    # rename samples in varscan vcf
    printf "TUMOR ${TumorReplicateId}\nNORMAL ${NormalReplicateId}\n" > vcf_rename_${TumorReplicateId}_${NormalReplicateId}_tmp

    bcftools reheader \\
        -s vcf_rename_${TumorReplicateId}_${NormalReplicateId}_tmp \\
        ${TumorReplicateId}_varscan_combined_sorted.vcf.gz \\
        > ${TumorReplicateId}_${NormalReplicateId}_varscan.Somatic.hc.filtered.vcf.gz

    tabix -p vcf ${TumorReplicateId}_${NormalReplicateId}_varscan.Somatic.hc.filtered.vcf.gz
    rm -f vcf_rename_${TumorReplicateId}_${NormalReplicateId}_tmp

    """

}

if(have_Mutect1) {
    // Mutect1: calls SNPS from tumor and matched normal sample
    process 'Mutect1scattered' {

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/mutect1/processing/",
            mode: params.publishDirMode,
            enabled: params.fullOutput

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(Tumorbam),
            file(Tumorbai),
            file(Normalbam),
            file(Normalbai),
            file(intervals)
        ) from GatherRealignedBamFiles_out_Mutect1scattered_ch0
            .combine(
                SplitIntervals_out_ch6.flatten()
            )

        set(
            file(RefFasta),
            file(RefIdx),
            file(RefDict),
        ) from Channel.value(
            [ reference.RefFasta,
            reference.RefIdx,
            reference.RefDict ]
        )


        set(
            file(DBSNP),
            file(DBSNPIdx)
        ) from Channel.value(
            [ database.DBSNP,
              database.DBSNPIdx ]
        )

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${TumorReplicateId}_${intervals}.raw.vcf.gz"),
            file("${TumorReplicateId}_${intervals}.raw.stats.txt"),
            file("${TumorReplicateId}_${intervals}.raw.vcf.gz.idx")
        ) into Mutect1scattered_out_ch0

        script:
        cosmic = ( file(params.databases.Cosmic).exists() &&
                   file(params.databases.CosmicIdx).exists()
                 ) ? "--cosmic " + file(params.databases.Cosmic)
                   : ""
        """
        mkdir -p ${tmpDir}

        $JAVA7 ${params.JAVA_Xmx} -Djava.io.tmpdir=${tmpDir} -jar $MUTECT1 \\
            --analysis_type MuTect \\
            --reference_sequence ${RefFasta} \\
            ${cosmic} \\
            --dbsnp ${DBSNP} \\
            -L ${intervals} \\
            --input_file:normal ${Normalbam} \\
            --input_file:tumor ${Tumorbam} \\
            --out ${TumorReplicateId}_${intervals}.raw.stats.txt \\
            --vcf ${TumorReplicateId}_${intervals}.raw.vcf.gz
        """
    }

    // Merge scattered Mutect1 vcfs
    process 'gatherMutect1VCFs' {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/mutect1/",
            saveAs: {
                fileName ->
                    if(fileName.indexOf("_mutect1_raw") >= 0) {
                        targetFile = "raw/" + fileName
                    } else {
                        targetFile = fileName
                    }
                    return targetFile
            },
            mode: params.publishDirMode

        input:
        set(
            file(RefFasta),
            file(RefIdx),
            file(RefDict)
        ) from Channel.value(
            [ reference.RefFasta,
            reference.RefIdx,
            reference.RefDict ]
        )

        set(
            TumorReplicateId,
            NormalReplicateId,
            file(vcf),
            file(stats),
            file(idx)
        ) from Mutect1scattered_out_ch0
            .toSortedList({a, b -> a[2].baseName <=> b[2].baseName})
            .flatten()
            .collate(5)
            .groupTuple(by: [0,1])


        output:
        file("${TumorReplicateId}_${NormalReplicateId}_mutect1_raw.vcf.gz")
        file("${TumorReplicateId}_${NormalReplicateId}_mutect1_raw.vcf.gz.tbi")
        file("${TumorReplicateId}_${NormalReplicateId}_mutect1_raw.stats.txt")

        set(
            TumorReplicateId,
            NormalReplicateId,
            val("mutect1"),
            file("${TumorReplicateId}_${NormalReplicateId}_mutect1_final.vcf.gz"),
            file("${TumorReplicateId}_${NormalReplicateId}_mutect1_final.vcf.gz.tbi")
        ) into (
            Mutect1_out_ch0,
            Mutect1_out_ch1
        )


        script:
        java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'
        """
        mkdir -p ${tmpDir}

        gatk --java-options ${java_opts} MergeVcfs \\
            --TMP_DIR ${tmpDir} \\
            -I ${vcf.join(" -I ")} \\
            -O ${TumorReplicateId}_${NormalReplicateId}_mutect1_raw.vcf.gz

        gatk SelectVariants \\
            --tmp-dir ${tmpDir} \\
            --variant ${TumorReplicateId}_${NormalReplicateId}_mutect1_raw.vcf.gz \\
            -R ${RefFasta} \\
            --exclude-filtered true \\
            --select 'vc.getGenotype(\"${TumorReplicateId}\").getAD().1 >= ${params.minAD}' \\
            --output ${TumorReplicateId}_${NormalReplicateId}_mutect1_final.vcf.gz


        head -2 ${stats[0]} > ${TumorReplicateId}_${NormalReplicateId}_mutect1_raw.stats.txt
        tail -q -n +3 ${stats.join(" ")} >> ${TumorReplicateId}_${NormalReplicateId}_mutect1_raw.stats.txt
        """
    }
} else {

    log.info "INFO: Mutect1 not available, skipping...."

    Channel.empty().set { Mutect1_out_ch0 }

    GatherRealignedBamFiles_out_Mutect1scattered_ch0
        .map {  item -> tuple(item[0],
                              item[1],
                              "mutect1",
                              "NO_FILE",
                              "NO_FILE_IDX") }
        .set { Mutect1_out_ch1 }

} // END if have MUTECT1

// Strelka2 and Manta
if (! single_end) {
    process 'MantaSomaticIndels' {

        label 'Manta'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/manta/",
            saveAs: {
                filename ->
                    if((filename.indexOf("_diploidSV.vcf") > 0 ||
                        filename.indexOf("_svCandidateGenerationStats.tsv") > 0 ||
                        filename.indexOf("_candidateSV.vcf") > 0) && params.fullOutput) {
                        return "allSV/$filename"
                    } else if((filename.indexOf("_diploidSV.vcf") > 0 ||
                               filename.indexOf("_svCandidateGenerationStats.tsv") > 0 ||
                               filename.indexOf("_candidateSV.vcf") > 0) && ! params.fullOutput) {
                        return null
                    } else {
                        return "$filename"
                    }
            },
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(Tumorbam),
            file(Tumorbai),
            file(Normalbam),
            file(Normalbai),
            file(RegionsBedGz),
            file(RegionsBedGzTbi)
        ) from BaseRecalGATK4_out_MantaSomaticIndels_ch0
            .combine(RegionsBedToTabix_out_ch1)

        set(
            file(RefFasta),
            file(RefIdx),
            file(RefDict)
        ) from Channel.value(
            [ reference.RefFasta,
            reference.RefIdx,
            reference.RefDict ]
        )

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${TumorReplicateId}_${NormalReplicateId}_candidateSmallIndels.vcf.gz"),
            file("${TumorReplicateId}_${NormalReplicateId}_candidateSmallIndels.vcf.gz.tbi")
        ) into MantaSomaticIndels_out_ch0
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${TumorReplicateId}_${NormalReplicateId}_somaticSV.vcf.gz"),
            file("${TumorReplicateId}_${NormalReplicateId}_somaticSV.vcf.gz.tbi")
        ) into MantaSomaticIndels_out_NeoFuse_in_ch0


        file("${TumorReplicateId}_${NormalReplicateId}_diploidSV.vcf.gz")
        file("${TumorReplicateId}_${NormalReplicateId}_diploidSV.vcf.gz.tbi")
        file("${TumorReplicateId}_${NormalReplicateId}_candidateSV.vcf.gz")
        file("${TumorReplicateId}_${NormalReplicateId}_candidateSV.vcf.gz.tbi")
        file("${TumorReplicateId}_${NormalReplicateId}_candidateSmallIndels.vcf.gz")
        file("${TumorReplicateId}_${NormalReplicateId}_candidateSmallIndels.vcf.gz.tbi")
        file("${TumorReplicateId}_${NormalReplicateId}_svCandidateGenerationStats.tsv")
        file("${TumorReplicateId}_${NormalReplicateId}_somaticSV.vcf.gz")
        file("${TumorReplicateId}_${NormalReplicateId}_somaticSV.vcf.gz.tbi")

        script:
        exome_options = params.WES ? "--callRegions ${RegionsBedGz} --exome" : ""

        """
        configManta.py --tumorBam ${Tumorbam} --normalBam  ${Normalbam} \\
            --referenceFasta ${RefFasta} \\
            --runDir manta_${TumorReplicateId} ${exome_options}
        manta_${TumorReplicateId}/runWorkflow.py -m local -j ${task.cpus}
        cp manta_${TumorReplicateId}/results/variants/diploidSV.vcf.gz ${TumorReplicateId}_${NormalReplicateId}_diploidSV.vcf.gz
        cp manta_${TumorReplicateId}/results/variants/diploidSV.vcf.gz.tbi ${TumorReplicateId}_${NormalReplicateId}_diploidSV.vcf.gz.tbi
        cp manta_${TumorReplicateId}/results/variants/candidateSV.vcf.gz ${TumorReplicateId}_${NormalReplicateId}_candidateSV.vcf.gz
        cp manta_${TumorReplicateId}/results/variants/candidateSV.vcf.gz.tbi ${TumorReplicateId}_${NormalReplicateId}_candidateSV.vcf.gz.tbi
        cp manta_${TumorReplicateId}/results/variants/candidateSmallIndels.vcf.gz ${TumorReplicateId}_${NormalReplicateId}_candidateSmallIndels.vcf.gz
        cp manta_${TumorReplicateId}/results/variants/candidateSmallIndels.vcf.gz.tbi ${TumorReplicateId}_${NormalReplicateId}_candidateSmallIndels.vcf.gz.tbi
        cp manta_${TumorReplicateId}/results/variants/somaticSV.vcf.gz ${TumorReplicateId}_${NormalReplicateId}_somaticSV.vcf.gz
        cp manta_${TumorReplicateId}/results/variants/somaticSV.vcf.gz.tbi ${TumorReplicateId}_${NormalReplicateId}_somaticSV.vcf.gz.tbi
        cp manta_${TumorReplicateId}/results/stats/svCandidateGenerationStats.tsv ${TumorReplicateId}_${NormalReplicateId}_svCandidateGenerationStats.tsv
        """
    }
} else {
    BaseRecalGATK4_out_MantaSomaticIndels_ch0
        .map {  item -> tuple(item[0],
                              item[1],
                              "NO_FILE",
                              "NO_FILE_IDX") }
        .into { MantaSomaticIndels_out_ch0;  MantaSomaticIndels_out_NeoFuse_in_ch0 }
}

process StrelkaSomatic {

    label 'Strelka'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/strelka/",
        saveAs: { filename -> filename.indexOf("_runStats") > 0 ? "stats/$filename" : "raw/$filename"},
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(Tumorbam),
        file(Tumorbai),
        file(Normalbam),
        file(Normalbai),
        file(manta_indel),
        file(manta_indel_tbi),
        file(RegionsBedGz),
        file(RegionsBedGzTbi)
    ) from BaseRecalGATK4_out_StrelkaSomatic_ch0
        .combine(MantaSomaticIndels_out_ch0, by:[0,1])
        .combine(RegionsBedToTabix_out_ch0)

    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    output:
    tuple(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_somatic.snvs.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_somatic.snvs.vcf.gz.tbi"),
        file("${TumorReplicateId}_${NormalReplicateId}_somatic.indels.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_somatic.indels.vcf.gz.tbi"),
    ) into (
        StrelkaSomatic_out_ch0
    )
    file("${TumorReplicateId}_${NormalReplicateId}_runStats.tsv")
    file("${TumorReplicateId}_${NormalReplicateId}_runStats.xml")

    script:
    manta_indel_candidates = single_end ? "" : "--indelCandidates ${manta_indel}"
    exome_options = params.WES ? "--callRegions ${RegionsBedGz} --exome" : ""

    """
    configureStrelkaSomaticWorkflow.py --tumorBam ${Tumorbam} --normalBam  ${Normalbam} \\
        --referenceFasta ${RefFasta} \\
        ${manta_indel_candidates} \\
        --runDir strelka_${TumorReplicateId} ${exome_options}
    strelka_${TumorReplicateId}/runWorkflow.py -m local -j ${task.cpus}
    cp strelka_${TumorReplicateId}/results/variants/somatic.indels.vcf.gz ${TumorReplicateId}_${NormalReplicateId}_somatic.indels.vcf.gz
    cp strelka_${TumorReplicateId}/results/variants/somatic.indels.vcf.gz.tbi ${TumorReplicateId}_${NormalReplicateId}_somatic.indels.vcf.gz.tbi
    cp strelka_${TumorReplicateId}/results/variants/somatic.snvs.vcf.gz ${TumorReplicateId}_${NormalReplicateId}_somatic.snvs.vcf.gz
    cp strelka_${TumorReplicateId}/results/variants/somatic.snvs.vcf.gz.tbi ${TumorReplicateId}_${NormalReplicateId}_somatic.snvs.vcf.gz.tbi
    cp strelka_${TumorReplicateId}/results/stats/runStats.tsv ${TumorReplicateId}_${NormalReplicateId}_runStats.tsv
    cp strelka_${TumorReplicateId}/results/stats/runStats.xml ${TumorReplicateId}_${NormalReplicateId}_runStats.xml

    """
}

process 'finalizeStrelkaVCF' {
    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/strelka/",
        saveAs: { filename -> filename.indexOf("_strelka_combined_somatic.vcf.gz") > 0 ? "raw/$filename" : "$filename"},
        mode: params.publishDirMode


    input:
    tuple(
        TumorReplicateId,
        NormalReplicateId,
        file(somatic_snvs),
        file(somatic_snvs_tbi),
        file(somatic_indels),
        file(somatic_indels_tbi),
    ) from StrelkaSomatic_out_ch0

    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    output:
    tuple(
        TumorReplicateId,
        NormalReplicateId,
        val("strelka"),
        file("${TumorReplicateId}_${NormalReplicateId}_strelka_somatic_final.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_strelka_somatic_final.vcf.gz.tbi")
    ) into (
        StrelkaSomaticFinal_out_ch0,
        StrelkaSomaticFinal_out_ch1
    )
    file("${TumorReplicateId}_${NormalReplicateId}_strelka_combined_somatic.vcf.gz")

    script:
    java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'
    """

    gatk --java-options ${java_opts} MergeVcfs \\
        --TMP_DIR ${tmpDir} \\
        -I ${somatic_snvs} \\
        -I ${somatic_indels} \\
        -O ${TumorReplicateId}_${NormalReplicateId}_strelka_combined.vcf.gz \\
        --SEQUENCE_DICTIONARY ${RefDict}

    gatk --java-options ${java_opts} SortVcf \\
        --TMP_DIR ${tmpDir} \\
        -I ${TumorReplicateId}_${NormalReplicateId}_strelka_combined.vcf.gz \\
        -O ${TumorReplicateId}_${NormalReplicateId}_strelka_combined_sorted.vcf.gz \\
        --SEQUENCE_DICTIONARY ${RefDict}

    # rename samples in strelka vcf
    printf "TUMOR ${TumorReplicateId}\nNORMAL ${NormalReplicateId}\n" > vcf_rename_${TumorReplicateId}_${NormalReplicateId}_tmp

    bcftools reheader \\
        -s vcf_rename_${TumorReplicateId}_${NormalReplicateId}_tmp \\
        ${TumorReplicateId}_${NormalReplicateId}_strelka_combined_sorted.vcf.gz \\
        > ${TumorReplicateId}_${NormalReplicateId}_strelka_combined_somatic.vcf.gz

    tabix -p vcf ${TumorReplicateId}_${NormalReplicateId}_strelka_combined_somatic.vcf.gz
    rm -f vcf_rename_${TumorReplicateId}_${NormalReplicateId}_tmp

    gatk SelectVariants \\
        --tmp-dir ${tmpDir} \\
        --variant ${TumorReplicateId}_${NormalReplicateId}_strelka_combined_somatic.vcf.gz \\
        -R ${RefFasta} \\
        --exclude-filtered true \\
        --output ${TumorReplicateId}_${NormalReplicateId}_strelka_somatic_final.vcf.gz

    """
}

// END Strelka2 and Manta

/*
    Creates a VCF that is based on the primary caller (e.g. mutect2) vcf but that contains only variants
    that are confirmed by any of the confirming callers (e..g. mutect1, varscan)
*/
process 'mkHCsomaticVCF' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/high_confidence/",
        mode: params.publishDirMode

    input:
    file(RefDict) from Channel.value(reference.RefDict)

    set(
        TumorReplicateId,
        NormalReplicateId,
        _,
        file(Mutect2_VCF),
        file(Mutect2_Idx),
        _,
        file(Mutect1_VCF),
        file(Mutect1_Idx),
        _,
        file(VarScan_VCF),
        file(VarScan_Idx),
        _,
        file(Strelka_VCF),
        file(Strelka_IDX)
    ) from FilterMutect2_out_ch1
        .combine(Mutect1_out_ch1, by: [0, 1])
        .combine(MergeAndRenameSamplesInVarscanVCF_out_ch1, by: [0, 1])
        .combine(StrelkaSomaticFinal_out_ch0, by: [0, 1])

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        val("hc"),
        file("${TumorReplicateId}_${NormalReplicateId}_Somatic.hc.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_Somatic.hc.vcf.gz.tbi")
    ) into (
        mkHCsomaticVCF_out_ch0,
        mkHCsomaticVCF_out_ch1,
        mkHCsomaticVCF_out_ch2
    )

    script:
    callerMap = ["M2": Mutect2_VCF, "M1": Mutect1_VCF, "VS": VarScan_VCF, "ST": Strelka_VCF]

    if(!have_Mutect1) {
        callerMap.remove("M1")
    }

    primary_caller_file = callerMap[params.primaryCaller]

    callerMap.remove(params.primaryCaller)
    confirming_caller_files = callerMap.values().join(" ")
    confirming_caller_names = callerMap.keySet().join(" ")
    """
    make_hc_vcf.py \\
        --primary ${primary_caller_file} \\
        --primary_name ${params.primaryCaller} \\
        --confirming ${confirming_caller_files} \\
        --confirming_names ${confirming_caller_names} \\
        --out_vcf ${TumorReplicateId}_${NormalReplicateId}_Somatic.hc.vcf \\
        --out_single_vcf ${TumorReplicateId}_${NormalReplicateId}_Somatic.single.vcf

    bgzip -c ${TumorReplicateId}_${NormalReplicateId}_Somatic.hc.vcf > ${TumorReplicateId}_${NormalReplicateId}_Somatic.hc.vcf.gz
    tabix -p vcf ${TumorReplicateId}_${NormalReplicateId}_Somatic.hc.vcf.gz
    """

}

vep_cache_chck_file_name = "." + params.vep_species + "_" + params.vep_assembly + "_" + params.vep_cache_version + "_cache_ok.chck"
vep_cache_chck_file = file(params.databases.vep_cache + "/" + vep_cache_chck_file_name)
if(!vep_cache_chck_file.exists() || vep_cache_chck_file.isEmpty()) {

    log.warn "WARNING: VEP cache not installed, starting installation. This may take a while."

    process 'installVEPcache' {

        label 'VEP'

        tag 'installVEPcache'

        // do not cache
        cache false

        output:
        file("${vep_cache_chck_file_name}") into (
            vep_cache_ch0,
            vep_cache_ch1,
            vep_cache_ch2
        )

        script:
        if(!have_vep)
            """
            mkdir -p ${params.databases.vep_cache}
            vep_install \\
                -a cf \\
                -s ${params.vep_species} \\
                -y ${params.vep_assembly} \\
                -c ${params.databases.vep_cache} \\
                --CACHE_VERSION ${params.vep_cache_version} \\
                --CONVERT 2> vep_errors.txt && \\
            echo "OK" > ${vep_cache_chck_file_name} && \\
            cp -f  ${vep_cache_chck_file_name} ${vep_cache_chck_file}
            """
        else
            """
            echo "OK" > ${vep_cache_chck_file_name} && \\
            cp -f  ${vep_cache_chck_file_name} ${vep_cache_chck_file}
            """
    }

} else {

    vep_cache_ch = Channel.fromPath(vep_cache_chck_file)
    (vep_cache_ch0, vep_cache_ch1, vep_cache_ch2) = vep_cache_ch.into(3)

}

vep_plugins_chck_file_name = "." + params.vep_cache_version + "_plugins_ok.chck"
vep_plugins_chck_file = file(params.databases.vep_cache + "/" + vep_plugins_chck_file_name)
if(!vep_plugins_chck_file.exists() || vep_plugins_chck_file.isEmpty()) {

    log.warn "WARNING: VEP plugins not installed, starting installation. This may take a while."

    process 'installVEPplugins' {

        label 'VEP'

        tag 'installVEPplugins'

        // do not cache
        cache false

        input:
        file(vep_cache_chck_file) from vep_cache_ch2

        output:
        file("${vep_plugins_chck_file_name}") into (
            vep_plugins_ch0,
            vep_plugins_ch1
        )

        script:
        if(!have_vep)
            """
            mkdir -p ${params.databases.vep_cache}
            vep_install \\
                -a p \\
                -c ${params.databases.vep_cache} \\
                --PLUGINS all 2> vep_errors.txt && \\
            cp -f ${baseDir}/assets/Wildtype.pm ${params.databases.vep_cache}/Plugins && \\
            cp -f ${baseDir}/assets/Frameshift.pm ${params.databases.vep_cache}/Plugins && \\
            echo "OK" > ${vep_plugins_chck_file_name} && \\
            cp -f  ${vep_plugins_chck_file_name} ${vep_plugins_chck_file}
            """
        else
            """
            echo "OK" > ${vep_plugins_chck_file_name} && \\
            cp -f  ${vep_plugins_chck_file_name} ${vep_plugins_chck_file}
            """
    }

} else {

    vep_plugins_ch = Channel.fromPath(vep_plugins_chck_file)
    (vep_plugins_ch0, vep_plugins_ch1) = vep_plugins_ch.into(2)

}

// Variant Effect Prediction: using ensembl vep
process 'VepTab' {

    label 'VEP'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/05_vep/tables/",
        saveAs: {
            filename ->
                (filename.indexOf("$CallerName") > 0 && CallerName != "hc")
                ? "$CallerName/$filename"
                : "high_confidence/$filename"
        },
        mode: params.publishDirMode

    input:

    set(
        TumorReplicateId,
        NormalReplicateId,
        CallerName,
        file(Vcf),
        file(Idx),
        file(vep_cache_chck_file),
        file(vep_plugin_chck_file)
    ) from FilterMutect2_out_ch0
        .concat(MergeAndRenameSamplesInVarscanVCF_out_ch0)
        .concat(Mutect1_out_ch0)
        .concat(StrelkaSomaticFinal_out_ch1)
        .concat(mkHCsomaticVCF_out_ch0)
        .flatten()
        .collate(5)
        .combine(vep_cache_ch0)
        .combine(vep_plugins_ch0)

    output:
    file("${TumorReplicateId}_${NormalReplicateId}_${CallerName}_vep.txt")
    file("${TumorReplicateId}_${NormalReplicateId}_${CallerName}_vep_summary.html")

    script:
    """
    vep -i ${Vcf} \\
        -o ${TumorReplicateId}_${NormalReplicateId}_${CallerName}_vep.txt \\
        --fork ${task.cpus} \\
        --stats_file ${TumorReplicateId}_${NormalReplicateId}_${CallerName}_vep_summary.html \\
        --species ${params.vep_species} \\
        --assembly ${params.vep_assembly} \\
        --offline \\
        --dir ${params.databases.vep_cache} \\
        --cache \\
        --cache_version ${params.vep_cache_version} \\
        --dir_cache ${params.databases.vep_cache} \\
        --fasta ${params.references.VepFasta} \\
        --format "vcf" \\
        ${params.vep_options} \\
        --tab 2> vep_errors.txt
    """
}

// CREATE phased VCF
/*
    make phased vcf for pVACseq using tumor and germline variants:
    based on https://pvactools.readthedocs.io/en/latest/pvacseq/input_file_prep/proximal_vcf.html
*/

// combined germline and somatic variants
process 'mkCombinedVCF' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/high_confidence_readbacked_phased/processing/",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict ]
    )

    set(
        TumorReplicateId,
        NormalReplicateId,
        file(germlineVCF),
        file(germlineVCFidx),
        _,
        file(tumorVCF),
        file(tumorVCFidx)
    ) from FilterGermlineVariantTranches_out_ch0
        .combine(mkHCsomaticVCF_out_ch1, by: [0,1])          // uses confirmed mutect2 variants

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined_sorted.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined_sorted.vcf.gz.tbi"),
    ) into mkCombinedVCF_out_ch


    script:
    java_opts = '"' + params.JAVA_Xmx + ' -XX:ParallelGCThreads=' + task.cpus + '"'
    """
    mkdir -p ${tmpDir}

    gatk --java-options ${params.JAVA_Xmx} SelectVariants \\
        --tmp-dir ${tmpDir} \\
        -R ${RefFasta} \\
        -V ${tumorVCF} \\
        --sample-name ${TumorReplicateId} \\
        -O ${TumorReplicateId}_${NormalReplicateId}_tumor.vcf.gz

    gatk --java-options ${java_opts} RenameSampleInVcf \\
        --TMP_DIR ${tmpDir} \\
        -I ${germlineVCF} \\
        --NEW_SAMPLE_NAME ${TumorReplicateId} \\
        -O ${NormalReplicateId}_germlineVAR_rename2tumorID.vcf.gz

    gatk --java-options ${java_opts} MergeVcfs \\
        --TMP_DIR ${tmpDir} \\
        -I ${TumorReplicateId}_${NormalReplicateId}_tumor.vcf.gz \\
        -I ${NormalReplicateId}_germlineVAR_rename2tumorID.vcf.gz \\
        -O ${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined.vcf.gz

    gatk --java-options ${java_opts} SortVcf \\
        --TMP_DIR ${tmpDir} \\
        -I ${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined.vcf.gz \\
        -O ${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined_sorted.vcf.gz \\
        --SEQUENCE_DICTIONARY ${RefDict}
    """
}

process 'VEPvcf' {

    label 'VEP'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/05_vep/vcf/high_confidence/",
        saveAs: {
            filename ->
                if (filename.indexOf("_vep_pick.vcf.gz") > 0 && params.fullOutput) {
                    return "combined/$filename"
                } else if (filename.indexOf("_vep_pick.vcf.gz") > 0 && ! params.fullOutput) {
                    return null
                } else if (filename.endsWith(".fa")) {
                    return "$params.outputDir/analyses/$TumorReplicateId/06_proteinseq/$filename"
                } else {
                    return "$filename"
                }
        },
        mode: params.publishDirMode

    input:
    set (
        TumorReplicateId,
        NormalReplicateId,
        file(combinedVCF),
        file(combinedVCFidx),
        _,
        file(tumorVCF),
        file(tumorVCFidx),
        file(vep_cache_chck_file),
        file(vep_plugin_chck_file)
    ) from mkCombinedVCF_out_ch
        .combine(mkHCsomaticVCF_out_ch2, by: [0,1])
        .combine(vep_cache_ch1)
        .combine(vep_plugins_ch1)

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined_sorted_vep_pick.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined_sorted_vep_pick.vcf.gz.tbi"),
    ) into (
        VEPvcf_out_ch0
    )

    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_tumor_vep_pick.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_tumor_vep_pick.vcf.gz.tbi")
    ) into (
        VEPvcf_out_ch2,
    )
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_tumor_vep.vcf.gz"),
        file("${TumorReplicateId}_${NormalReplicateId}_tumor_vep.vcf.gz.tbi")
    ) into (
        VEPvcf_out_ch1, // mkPhasedVCF_out_Clonality_ch0
        VEPvcf_out_ch3,
        VEPvcf_out_ch4
    )
    file("${TumorReplicateId}_${NormalReplicateId}_tumor_reference.fa")
    file("${TumorReplicateId}_${NormalReplicateId}_tumor_mutated.fa")



    script:
    """
    mkdir -p ${tmpDir}

    # pVACSeq
    vep -i ${combinedVCF} \\
        -o ${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined_sorted_vep_pick.vcf \\
        --fork ${task.cpus} \\
        --stats_file ${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined_sorted_vep_summary_pick.html \\
        --species ${params.vep_species} \\
        --assembly ${params.vep_assembly} \\
        --offline \\
        --cache \\
        --cache_version ${params.vep_cache_version} \\
        --dir ${params.databases.vep_cache} \\
        --dir_cache ${params.databases.vep_cache} \\
        --hgvs \\
        --fasta ${params.references.VepFasta} \\
        --pick --plugin Frameshift --plugin Wildtype \\
        --symbol --terms SO --transcript_version --tsl \\
        --format vcf \\
        --vcf 2> vep_errors_0.txt

    # pVACSeq
    vep -i ${tumorVCF} \\
        -o ${TumorReplicateId}_${NormalReplicateId}_tumor_vep_pick.vcf \\
        --fork ${task.cpus} \\
        --stats_file ${TumorReplicateId}_${NormalReplicateId}_tumor_vep_summary_pick.html \\
        --species ${params.vep_species} \\
        --assembly ${params.vep_assembly} \\
        --offline \\
        --cache \\
        --cache_version ${params.vep_cache_version} \\
        --dir ${params.databases.vep_cache} \\
        --dir_cache ${params.databases.vep_cache} \\
        --hgvs \\
        --fasta ${params.references.VepFasta} \\
        --pick --plugin Frameshift --plugin Wildtype \\
        --symbol --terms SO --transcript_version --tsl \\
        --vcf 2>> vep_errors_1.txt

    # All variants
    vep -i ${tumorVCF} \\
        -o ${TumorReplicateId}_${NormalReplicateId}_tumor_vep.vcf \\
        --fork ${task.cpus} \\
        --stats_file ${TumorReplicateId}_${NormalReplicateId}_tumor_vep_summary.html \\
        --species ${params.vep_species} \\
        --assembly ${params.vep_assembly} \\
        --offline \\
        --cache \\
        --cache_version ${params.vep_cache_version} \\
        --dir ${params.databases.vep_cache} \\
        --dir_cache ${params.databases.vep_cache} \\
        --hgvs \\
        --fasta ${params.references.VepFasta} \\
        --plugin ProteinSeqs,${TumorReplicateId}_${NormalReplicateId}_tumor_reference.fa,${TumorReplicateId}_${NormalReplicateId}_tumor_mutated.fa \\
        --symbol --terms SO --transcript_version --tsl \\
        --vcf 2>> vep_errors_1.txt


    bgzip -c ${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined_sorted_vep_pick.vcf \\
        > ${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined_sorted_vep_pick.vcf.gz

    tabix -p vcf ${TumorReplicateId}_${NormalReplicateId}_germlineVAR_combined_sorted_vep_pick.vcf.gz && \\
        sleep 2

    bgzip -c ${TumorReplicateId}_${NormalReplicateId}_tumor_vep_pick.vcf \\
        > ${TumorReplicateId}_${NormalReplicateId}_tumor_vep_pick.vcf.gz

    tabix -p vcf ${TumorReplicateId}_${NormalReplicateId}_tumor_vep_pick.vcf.gz && \\
        sleep 2

    bgzip -c ${TumorReplicateId}_${NormalReplicateId}_tumor_vep.vcf \\
        > ${TumorReplicateId}_${NormalReplicateId}_tumor_vep.vcf.gz

    tabix -p vcf ${TumorReplicateId}_${NormalReplicateId}_tumor_vep.vcf.gz && \\
        sleep 2

    sync
    """
}

if(have_GATK3) {
    process 'ReadBackedphasing' {

        label 'GATK3'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/04_variations/high_confidence_readbacked_phased/",
            mode: params.publishDirMode

        input:
        set (
            TumorReplicateId,
            NormalReplicateId,
            file(tumorBAM),
            file(tumorBAI),
            file(combinedVCF),
            file(combinedVCFidx)
        ) from GatherRealignedBamFilesTumor_out_mkPhasedVCF_ch0
            .combine(VEPvcf_out_ch0, by: [0,1])

        set(
            file(RefFasta),
            file(RefIdx),
            file(RefDict)
        ) from Channel.value(
            [ reference.RefFasta,
            reference.RefIdx,
            reference.RefDict ]
        )

        output:
        set (
            TumorReplicateId,
            NormalReplicateId,
            file("${TumorReplicateId}_${NormalReplicateId}_vep_phased.vcf.gz"),
            file("${TumorReplicateId}_${NormalReplicateId}_vep_phased.vcf.gz.tbi")
        ) into (
            mkPhasedVCF_out_ch0,
            mkPhasedVCF_out_pVACseq_ch0,
            generate_protein_fasta_phased_vcf_ch0
        )

        script:
        """
        $JAVA8 -XX:ParallelGCThreads=${task.cpus} -Djava.io.tmpdir=${tmpDir} -jar $GATK3 \\
            -T ReadBackedPhasing \\
            -R ${RefFasta} \\
            -I ${tumorBAM} \\
            -V ${combinedVCF} \\
            -L ${combinedVCF} \\
            -o ${TumorReplicateId}_${NormalReplicateId}_vep_phased.vcf.gz
        """
    }
} else {

    log.warn "WARNING: GATK3 not installed! Can not generate readbacked phased VCF:\n" +
        "You should manually review the sequence data for all candidates (e.g. in IGV) for proximal variants and\n" +
        " either account for these manually, or eliminate these candidates. Failure to do so may lead to inclusion\n" +
        " of incorrect peptide sequences."

    (mkPhasedVCF_out_ch0, mkPhasedVCF_out_pVACseq_ch0, generate_protein_fasta_phased_vcf_ch0) = VEPvcf_out_ch0.into(3)
}
// END CREATE phased VCF


// CNVs: ASCAT + FREEC


// adopted from sarek nfcore
process AlleleCounter {

    label 'AlleleCounter'

    tag "$TumorReplicateId - $NormalReplicateId"

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(BAM),
        file(BAI)
    ) from GatherRealignedBamFiles_out_AlleleCounter_ch0

    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict),
        file(acLoci)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict,
          reference.acLoci ]
    )

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        sampleType,
        file(outFileName)
    ) into AlleleCounter_out_ch0


    script:
    outFileName = (sampleType == "T") ? TumorReplicateId + ".alleleCount" : NormalReplicateId + ".alleleCount"
    if(single_end)
        """
        alleleCounter \\
            -l ${acLoci} \\
            -d \\
            -r ${RefFasta} \\
            -b ${BAM} \\
            -f 0 \\
            -o ${outFileName}
        """
    else
        """
        alleleCounter \\
            -l ${acLoci} \\
            -d \\
            -r ${RefFasta} \\
            -b ${BAM} \\
            -o ${outFileName}
        """
}

alleleCountOutNormal = Channel.create()
alleleCountOutTumor = Channel.create()

AlleleCounter_out_ch0
    .choice(
        alleleCountOutTumor, alleleCountOutNormal
    ) { it[2] == "T" ? 0 : 1 }

AlleleCounter_out_ch = alleleCountOutTumor.combine(alleleCountOutNormal, by: [0,1])

AlleleCounter_out_ch = AlleleCounter_out_ch
    .map{ TumorReplicateId, NormalReplicateId, sampleTypeT, alleleCountTumor, sampleTypeN, alleleCountNormal -> tuple(
            TumorReplicateId, NormalReplicateId, alleleCountTumor, alleleCountNormal
        )}



// R script from Malin Larssons bitbucket repo:
// https://bitbucket.org/malinlarsson/somatic_wgs_pipeline
process ConvertAlleleCounts {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/08_CNVs/ASCAT/processing",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(alleleCountTumor),
        file(alleleCountNormal),
    ) from AlleleCounter_out_ch


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}.BAF"),
        file("${TumorReplicateId}.LogR"),
        file("${NormalReplicateId}.BAF"),
        file("${NormalReplicateId}.LogR")
    ) into ConvertAlleleCounts_out_ch

    script:
    sex = sexMap[TumorReplicateId]
    """
    Rscript ${baseDir}/bin/convertAlleleCounts.r \\
        ${TumorReplicateId} ${alleleCountTumor} ${NormalReplicateId} ${alleleCountNormal} ${sex}
    """
}

// R scripts from Malin Larssons bitbucket repo:
// https://bitbucket.org/malinlarsson/somatic_wgs_pipeline
process 'Ascat' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/08_CNVs/ASCAT/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(bafTumor),
        file(logrTumor),
        file(bafNormal),
        file(logrNormal)
    ) from ConvertAlleleCounts_out_ch

    file(acLociGC) from Channel.value(reference.acLociGC)

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}.cnvs.txt"),
        file("${TumorReplicateId}.purityploidy.txt"),
    ) into Ascat_out_Clonality_ch0
    file("${TumorReplicateId}.*.{png,txt}")


    script:
    def sex = sexMap[TumorReplicateId]
    """
    # get rid of "chr" string if there is any
    for f in *BAF *LogR; do sed 's/chr//g' \$f > tmpFile; mv tmpFile \$f;done
    Rscript ${baseDir}/bin/run_ascat.r ${bafTumor} ${logrTumor} ${bafNormal} ${logrNormal} ${TumorReplicateId} ${baseDir} ${acLociGC} ${sex}
    """
}

(Ascat_out_Clonality_ch1, Ascat_out_Clonality_ch0) = Ascat_out_Clonality_ch0.into(2)

if (params.controlFREEC) {
    process 'Mpileup4ControFREEC' {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId - $NormalReplicateId"

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            sampleType,
            file(BAM),
            file(BAI)
        ) from GatherRealignedBamFiles_out_Mpileup4ControFREEC_ch0

        each file(interval) from ScatteredIntervalListToBed_out_ch1.flatten()


        set(
            file(RefFasta),
            file(RefIdx),
            file(RefDict),
        ) from Channel.value(
            [ reference.RefFasta,
            reference.RefIdx,
            reference.RefDict ]
        )

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            sampleType,
            file("${TumorReplicateId}_${NormalReplicateId}_${sampleType}_${interval}.pileup.gz")
        ) into Mpileup4ControFREEC_out_ch0

        script:
        """
        samtools mpileup \\
            -q 1 \\
            -f ${RefFasta} \\
            -l ${interval} \\
            ${BAM} | \\
        bgzip --threads ${task.cpus} -c > ${TumorReplicateId}_${NormalReplicateId}_${sampleType}_${interval}.pileup.gz
        """


    }

    Mpileup4ControFREEC_out_ch0 = Mpileup4ControFREEC_out_ch0.groupTuple(by:[0, 1, 2])

    // Merge scattered Varscan vcfs
    process 'gatherMpileups' {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId - $NormalReplicateId"

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            sampleType,
            file(mpileup)
        ) from Mpileup4ControFREEC_out_ch0

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            sampleType,
            file(outFileName)
        ) into gatherMpileups_out_ch0

        script:
        outFileName = (sampleType == "T") ? TumorReplicateId + ".pileup.gz" : NormalReplicateId + ".pileup.gz"
        """
        scatters=`ls -1v *.pileup.gz`
        zcat \$scatters | \\
        bgzip --threads ${task.cpus} -c > ${outFileName}
        """
    }

    mpileupOutNormal = Channel.create()
    mpileupOutTumor = Channel.create()

    gatherMpileups_out_ch0
        .choice(
            mpileupOutTumor, mpileupOutNormal
        ) { it[2] == "T" ? 0 : 1 }

    gatherMpileups_out_ch0 = mpileupOutTumor.combine(mpileupOutNormal, by: [0,1])

    // run ControlFREEC : adopted from nfcore sarek
    process 'ControlFREEC' {

        label 'Freec'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/08_CNVs/controlFREEC/",
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            _,
            file(mpileupTumor),
            _,
            file(mpileupNormal)
        ) from gatherMpileups_out_ch0

        set(
            file(RefChrDir),
            file(RefChrLen),
            file(DBSNP),
            file(DBSNPIdx)
        ) from Channel.value(
            [ reference.RefChrDir,
            reference.RefChrLen,
            database.DBSNP,
            database.DBSNPIdx ]
        )

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${TumorReplicateId}.pileup.gz_CNVs"),
            file("${TumorReplicateId}.pileup.gz_ratio.txt"),
            file("${TumorReplicateId}.pileup.gz_BAF.txt")
        ) into ControlFREEC_out_ch0

        script:
        config = "${TumorReplicateId}_vs_${NormalReplicateId}.config.txt"
        sex = sexMap[TumorReplicateId]

        read_orientation = (single_end) ? "0" : "FR"
        minimalSubclonePresence = (params.WES) ? 30 : 20
        degree = (params.WES) ? 1 : 4
        noisyData = (params.WES) ? "TRUE" : "FALSE"
        window = (params.WES) ? 0 : 50000
        breakPointType = (params.WES) ? 4 : 2
        breakPointThreshold = (params.WES) ? "1.2" : "0.8"
        printNA = (params.WES) ? "FALSE" :  "TRUE"
        readCountThreshold = (params.WES) ? 50 : 10
        minimalCoveragePerPosition = (params.WES) ? 5 : 0
        captureRegions = (params.WES) ? "captureRegions = ${reference.RegionsBed}" : ""
        """
        rm -f ${config}
        touch ${config}
        echo "[general]" >> ${config}
        echo "BedGraphOutput = TRUE" >> ${config}
        echo "chrFiles = \${PWD}/${RefChrDir.fileName}" >> ${config}
        echo "chrLenFile = \${PWD}/${RefChrLen.fileName}" >> ${config}
        echo "coefficientOfVariation = 0.05" >> ${config}
        echo "contaminationAdjustment = TRUE" >> ${config}
        echo "forceGCcontentNormalization = 0" >> ${config}
        echo "maxThreads = ${task.cpus}" >> ${config}
        echo "minimalSubclonePresence = ${minimalSubclonePresence}" >> ${config}
        echo "ploidy = 2,3,4" >> ${config}
        echo "degree = ${degree}" >> ${config}
        echo "noisyData = ${noisyData}" >> ${config}
        echo "sex = ${sex}" >> ${config}
        echo "window = ${window}" >> ${config}
        echo "breakPointType = ${breakPointType}" >> ${config}
        echo "breakPointThreshold = ${breakPointThreshold}" >> ${config}
        echo "printNA = ${printNA}" >> ${config}
        echo "readCountThreshold = ${readCountThreshold}" >> ${config}
        echo "" >> ${config}
        echo "[control]" >> ${config}
        echo "inputFormat = pileup" >> ${config}
        echo "mateFile = \${PWD}/${mpileupNormal}" >> ${config}
        echo "mateOrientation = ${read_orientation}" >> ${config}
        echo "" >> ${config}
        echo "[sample]" >> ${config}
        echo "inputFormat = pileup" >> ${config}
        echo "mateFile = \${PWD}/${mpileupTumor}" >> ${config}
        echo "mateOrientation = ${read_orientation}" >> ${config}
        echo "" >> ${config}
        echo "[BAF]" >> ${config}
        echo "SNPfile = ${DBSNP.fileName}" >> ${config}
        echo "minimalCoveragePerPosition = ${minimalCoveragePerPosition}" >> ${config}
        echo "" >> ${config}
        echo "[target]" >> ${config}
        echo "${captureRegions}" >> ${config}
        freec -conf ${config}
        """
    }


    process 'ControlFREECviz' {

        tag "$TumorReplicateId"

        // makeGraph.R and assess_significance.R seem to be instable
        errorStrategy 'ignore'

        publishDir "$params.outputDir/analyses/$TumorReplicateId/08_CNVs/controlFREEC/",
            mode: params.publishDirMode


        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(cnvTumor),
            file(ratioTumor),
            file(bafTumor),
        ) from ControlFREEC_out_ch0

        output:
        set(
            file("*.txt"),
            file("*.png"),
            file("*.bed"),
            file("*.circos")
        ) into ControlFREECviz_out_ch0


        script:
        """
        cat ${baseDir}/bin/assess_significance.R | R --slave --args ${cnvTumor} ${ratioTumor}
        cat ${baseDir}/bin/makeGraph.R | R --slave --args 2 ${ratioTumor} ${bafTumor}
        perl ${baseDir}/bin/freec2bed.pl -f ${ratioTumor} > ${TumorReplicateId}.bed
        perl ${baseDir}/bin/freec2circos.pl -f ${ratioTumor} > ${TumorReplicateId}.circos
        """
    }
}

Channel
    .fromPath(reference.RefChrLen)
    .splitCsv(sep: "\t")
    .map { row -> row[1] }
    .set { chromosomes_ch }

process 'SequenzaUtils' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(tumorBAM),
        file(tumorBAI),
        file(normalBAM),
        file(normalBAI)
    ) from GatherRealignedBamFiles_out_Sequenza_ch0
    each chromosome from chromosomes_ch

    set(
        file(RefFasta),
        file(RefIdx),
        file(RefDict),
        file(SequnzaGC)
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.RefDict,
          reference.SequenzaGC ]
    )

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${chromosome}_${TumorReplicateId}_seqz.gz")
    )  into SequenzaUtils_out_ch0

    script:
    """
    sequenza-utils \\
        bam2seqz \\
        --fasta ${RefFasta} \\
        --tumor ${tumorBAM} \\
        --normal ${normalBAM} \\
        -gc ${SequnzaGC} \\
        --chromosome ${chromosome} \\
        | \\
    sequenza-utils \\
        seqz_binning \\
        -w 50 \\
        -s - \\
        | \\
    bgzip \\
        --threads ${task.cpus} -c > ${chromosome}_${TumorReplicateId}_seqz.gz

    """
}

process gatherSequenzaInput {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/08_CNVs/Sequenza/processing",
        mode: params.publishDirMode,
        enabled: params.fullOutput

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(chromosome_seqz_binned)
    ) from SequenzaUtils_out_ch0
        .groupTuple(by: [0,1])


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_seqz.gz")
    ) into gatherSequenzaInput_out_ch0

    script:
    """
    first=1
    scatters=`ls -1v *_${TumorReplicateId}_seqz.gz`
    for f in \$scatters
    do
        if [ "\$first" ]
        then
            zcat "\$f"
            first=
        else
            zcat "\$f" | tail -n +2
        fi
    done | \\
    bgzip --threads ${task.cpus} -c > ${TumorReplicateId}_seqz.gz
    sync
    """
}

process Sequenza {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    errorStrategy "ignore"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/08_CNVs/Sequenza/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(seqz_file),
    ) from gatherSequenzaInput_out_ch0

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_segments.txt"),
        file("${TumorReplicateId}_confints_CP.txt")
    ) into Sequenza_out_Clonality_ch0
    file("${TumorReplicateId}_*.{png,pdf,txt}")

    script:
    sex = sexMap[TumorReplicateId]
    """
    Rscript \\
        ${baseDir}/bin/SequenzaScript.R \\
        ${seqz_file} \\
        ${TumorReplicateId} \\
        ${sex} || \\
        touch ${TumorReplicateId}_segments.txt && \\
        touch ${TumorReplicateId}_confints_CP.txt
    """
}

(Sequenza_out_Clonality_ch1, Sequenza_out_Clonality_ch0) = Sequenza_out_Clonality_ch0.into(2)

// get purity for CNVKit
purity_estimate = Ascat_out_Clonality_ch0.combine(Sequenza_out_Clonality_ch0, by: [0,1])
    .map {

        it ->
        def TumorReplicateId = it[0]
        def NormalReplicateId = it[1]
        def ascat_CNVs = it[2]
        def ascat_purity  = it[3]
        def seqz_CNVs  = it[4]
        def seqz_purity  = it[5]

        def ascatOK = true
        def sequenzaOK = true

        def purity = 1.0 // default
        def ploidy = 2.0 // default
        def sample_purity = 1.0 // default

        def fileReader = ascat_purity.newReader()

        def line = fileReader.readLine()
        line = fileReader.readLine()
        fileReader.close()
        if(line) {
            (purity, ploidy) = line.split("\t")
            if(purity == "0" || ploidy == "0" ) {
                ascatOK = false
            }
        } else {
            ascatOK = false
        }


        if(ascatOK && ! params.use_sequenza_cnvs) {
            sample_purity = purity
        } else {
            fileReader = seqz_purity.newReader()

            line = fileReader.readLine()
            if(line) {
                fields = line.split("\t")
                if(fields.size() < 3) {
                    sequenzaOK = false
                } else {
                    line = fileReader.readLine()
                    line = fileReader.readLine()
                    (purity, ploidy, _) = line.split("\t")
                }
            } else {
                sequenzaOK = false
            }
            fileReader.close()

            if(sequenzaOK) {
                sample_purity = purity
                log.warn "WARNING (" + TumorReplicateId + "): changed from ASCAT to Sequenza purity and segments, ASCAT did not produce results"
            } else {
                log.warn "WARNING (" + TumorReplicateId + "): neither ASCAT nor Sequenza produced results, using purity of 1.0"
            }
        }

        return [ TumorReplicateId, NormalReplicateId, sample_purity ]
    }

// CNVkit

process make_CNVkit_access_file {

    label 'CNVkit'

    tag 'mkCNVkitaccess'

    publishDir "$params.outputDir/supplemental/01_prepare_CNVkit/",
        mode: params.publishDirMode

    input:
    set(
        file(RefFasta),
        file(RefIdx),
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx ]
    )

    output:
    file(
        "access-5kb.${RefFasta.simpleName}.bed"
    ) into make_CNVkit_access_file_out_ch0

    script:
    """
    cnvkit.py \\
        access \\
        ${RefFasta} \\
        -s 5000 \\
        -o access-5kb.${RefFasta.simpleName}.bed
    """
}

process CNVkit {

    label 'CNVkit'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/08_CNVs/CNVkit/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(tumorBAM),
        file(tumorBAI),
        file(normalBAM),
        file(normalBAI),
        val(sample_purity)
    ) from MarkDuplicates_out_CNVkit_ch0
        .combine(purity_estimate, by: [0,1])

    file(CNVkit_accessFile) from make_CNVkit_access_file_out_ch0

    set(
        file(RefFasta),
        file(RefIdx),
        file(AnnoFile),
    ) from Channel.value(
        [ reference.RefFasta,
          reference.RefIdx,
          reference.AnnoFile ]
    )

    file(BaitsBed) from Channel.value(reference.BaitsBed)

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}*"),
        file("${NormalReplicateId}*")
    ) into CNVkit_out_ch0

    script:
    sex = sexMap[TumorReplicateId]
    maleRef = (sex in ["XY", "Male"]) ? "-y" : ""
    gender = (sex in ["XY", "Male"]) ? "Male" : "Female"
    method = (params.WES) ? "--method hybrid" : "--method wgs"
    targets = (params.WES) ? "--targets ${BaitsBed}" : ""

    """
    # set Agg as backend for matplotlib
    export MATPLOTLIBRC="./matplotlibrc"
    echo "backend : Agg" > \$MATPLOTLIBRC

    cnvkit.py \\
        batch \\
        ${tumorBAM} \\
        --normal ${normalBAM} \\
        ${method} \\
        ${targets} \\
        --fasta ${RefFasta} \\
        --annotate ${AnnoFile} \\
        --access ${CNVkit_accessFile} \\
        ${maleRef} \\
        -p ${task.cpus} \\
        --output-reference output_reference.cnn \\
        --output-dir ./

    cnvkit.py segmetrics \\
        -s ${tumorBAM.baseName}.cn{s,r} \\
        --ci \\
        --pi

    cnvkit.py call \\
        ${tumorBAM.baseName}.cns \\
        --filter ci \\
        -m clonal \\
        --purity ${sample_purity} \\
        --gender ${gender} \\
        -o ${tumorBAM.baseName}.call.cns

    cnvkit.py \\
        scatter \\
        ${tumorBAM.baseName}.cnr \\
        -s ${tumorBAM.baseName}.cns \\
        -o ${tumorBAM.baseName}_scatter.png

    cnvkit.py \\
        diagram \\
        ${tumorBAM.baseName}.cnr \\
        -s ${tumorBAM.baseName}.cns \\
        -o ${tumorBAM.baseName}_diagram.pdf

    cnvkit.py \\
        breaks \\
        ${tumorBAM.baseName}.cnr ${tumorBAM.baseName}.cns \\
        -o ${tumorBAM.baseName}_breaks.tsv

    cnvkit.py \\
        genemetrics \\
        ${tumorBAM.baseName}.cnr \\
        -s ${tumorBAM.baseName}.cns \\
        --gender ${gender} \\
        -t 0.2 -m 5 ${maleRef} \\
        -o ${tumorBAM.baseName}_gainloss.tsv

    # run PDF to PNG conversion if mogrify and gs is installed
    mogrify -version > /dev/null 2>&1 && \\
    gs -v > /dev/null 2>&1 && \\
        mogrify -density 600 -resize 2000 -format png *.pdf

    # clean up
    rm -f \$MATPLOTLIBRC
    """
}


clonality_input = Ascat_out_Clonality_ch1.combine(Sequenza_out_Clonality_ch1, by: [0, 1])
    .map {

        it ->
        def TumorReplicateId = it[0]
        def NormalReplicateId = it[1]
        def ascat_CNVs = it[2]
        def ascat_purity  = it[3]
        def seqz_CNVs  = it[4]
        def seqz_purity  = it[5]

        def ascatOK = true
        def sequenzaOK = true

        def fileReader = ascat_purity.newReader()

        def line = fileReader.readLine()
        line = fileReader.readLine()
        fileReader.close()
        if(line) {
            def (purity, ploidy) = line.split("\t")
            if(purity == "0" || ploidy == "0" ) {
                ascatOK = false
            }
        } else {
            ascatOK = false
        }

        fileReader = ascat_CNVs.newReader()

        def fields = ""
        line = fileReader.readLine()
        fileReader.close()
        if(line) {
            fields = line.split("\t")
            if(fields.size() < 5) {
                ascatOK = false
            }
        } else {
            ascatOK = false
        }


        fileReader = seqz_CNVs.newReader()

        line = fileReader.readLine()
        fileReader.close()
        if(line) {
            fields = line.split("\t")
            if(fields.size() < 13) {
                sequenzaOK = false
            }
        } else {
            sequenzaOK = false
        }

        fileReader = seqz_purity.newReader()

        line = fileReader.readLine()
        fileReader.close()
        if(line) {
            fields = line.split("\t")
            if(fields.size() < 3) {
                sequenzaOK = false
            }
        } else {
            sequenzaOK = false
        }

        return [ TumorReplicateId, NormalReplicateId, file(ascat_CNVs), file(ascat_purity), file(seqz_CNVs), file(seqz_purity), ascatOK, sequenzaOK ]
    }


process 'Clonality' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/09_CCF/",
        mode: params.publishDirMode

    cache 'lenient'

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(hc_vep_vcf),
        file(hc_vep_idx),
        file(ascat_CNVs),
        file(ascat_purity),
        file(seqz_CNVs),
        file(seqz_purity),
        val(ascatOK),
        val(sequenzaOK)
    ) from VEPvcf_out_ch1 // mkPhasedVCF_out_Clonality_ch0
        .combine(clonality_input, by: [0,1])


    output:
    set(
        TumorReplicateId,
        file("${TumorReplicateId}_CCFest.tsv"),
        val(ascatOK),
        val(sequenzaOK)
    ) into Clonality_out_ch0
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_CCFest.tsv"),
        val(ascatOK),
        val(sequenzaOK)
    ) into (
        ccf_ch0,
        ccf_ch1
    )

    script:
    def seg_opt = ""
    if (ascatOK && ! params.use_sequenza_cnvs) {
        seg_opt = "--seg ${ascat_CNVs}"
        purity_opt = "--purity ${ascat_purity}"
    } else if (sequenzaOK) {
        if(! params.use_sequenza_cnvs) {
            log.warn "WARNING: changed from ASCAT to Sequenza purity and segments, ASCAT did not produce results"
        }
        seg_opt = "--seg_sequenza ${seqz_CNVs}"
        purity_opt = "--purity_sequenza ${seqz_purity}"
    } else {
        log.warn "WARNING: neither ASCAT nor Sequenza did produce results"
    }

    if (ascatOK || sequenzaOK)
        """
        mkCCF_input.py \\
            --PatientID ${TumorReplicateId} \\
            --vcf ${hc_vep_vcf} \\
            ${seg_opt} \\
            ${purity_opt} \\
            --min_vaf 0.01 \\
            --result_table ${TumorReplicateId}_segments_CCF_input.txt && \\
        Rscript \\
            ${baseDir}/bin/CCF.R \\
            ${TumorReplicateId}_segments_CCF_input.txt \\
            ${TumorReplicateId}_CCFest.tsv \\
        """
    else
        """
        echo "Not avaliable" > ${TumorReplicateId}_CCFest.tsv
        """
}

// mutational burden all variants all covered positions
process 'MutationalBurden' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId - $NormalReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/07_MutationalBurden/",
        mode: params.publishDirMode

    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    maxRetries 5

    cache 'lenient'

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(Tumorbam),
        file(Tumorbai),
        file(Normalbam),
        file(Normalbai),
        file(vep_somatic_vcf_gz),
        file(vep_somatic_vcf_gz_tbi),
        file(ccf_file),
        val(ascatOK),
        val(sequenzaOK)
    ) from BaseRecalGATK4_out_MutationalBurden_ch0
        .combine(VEPvcf_out_ch3, by: [0,1])
        .combine(ccf_ch0, by: [0,1])


    output:
    set(
        TumorReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_mutational_burden.txt")
    ) into sample_info_tmb


    script:
    ccf_opts = ""

    if (ascatOK || sequenzaOK) {
        ccf_opts =  "--ccf ${ccf_file} --ccf_clonal_thresh ${params.CCFthreshold} --p_clonal_thresh ${params.pClonal}"
    }
    """
    mutationalLoad.py \\
        --normal_bam ${Normalbam} \\
        --tumor_bam ${Tumorbam} \\
        --vcf ${vep_somatic_vcf_gz} \\
        --min_coverage 5 \\
        --min_BQ 20 \\
        ${ccf_opts} \\
        --cpus ${task.cpus} \\
        --output_file ${TumorReplicateId}_${NormalReplicateId}_mutational_burden.txt
    """
}

// mutational burden coding variants coding (exons) covered positions
process 'MutationalBurdenCoding' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId - $NormalReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/07_MutationalBurden/",
        mode: params.publishDirMode

    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    maxRetries 5

    cache 'lenient'

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(Tumorbam),
        file(Tumorbai),
        file(Normalbam),
        file(Normalbai),
        file(vep_somatic_vcf_gz),
        file(vep_somatic_vcf_gz_tbi),
        file(ccf_file),
        val(ascatOK),
        val(sequenzaOK)
    ) from BaseRecalGATK4_out_MutationalBurden_ch1
        .combine(VEPvcf_out_ch4, by: [0,1])
        .combine(ccf_ch1, by: [0,1])
    file (exons) from Channel.value(reference.ExonsBED)


    output:
    set(
        TumorReplicateId,
        file("${TumorReplicateId}_${NormalReplicateId}_mutational_burden_coding.txt")
    ) into sample_info_tmb_coding


    script:
    ccf_opts = ""

    if (ascatOK || sequenzaOK) {
        ccf_opts =  "--ccf ${ccf_file} --ccf_clonal_thresh ${params.CCFthreshold} --p_clonal_thresh ${params.pClonal}"
    }
    """
    mutationalLoad.py \\
        --normal_bam ${Normalbam} \\
        --tumor_bam ${Tumorbam} \\
        --vcf ${vep_somatic_vcf_gz} \\
        --min_coverage 5 \\
        --min_BQ 20 \\
        --bed ${exons} \\
        --variant_type coding \\
        ${ccf_opts} \\
        --cpus ${task.cpus} \\
        --output_file ${TumorReplicateId}_${NormalReplicateId}_mutational_burden_coding.txt
    """
}


// END CNVs


// HLA TYPING

process 'mhc_extract' {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/10_HLA_typing/mhc_extract",
        mode: params.publishDirMode,
        saveAs: {
            filename ->
                if(filename.indexOf("NO_FILE") >= 0) {
                    return null
                } else {
                    return "$filename"
                }
        },
        enabled: params.fullOutput

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(tumor_BAM_aligned_sort_mkdp),
        file(tumor_BAI_aligned_sort_mkdp)
    ) from MarkDuplicatesTumor_out_ch0


    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${mhcReads_1}"),
        file("${mhcReads_2}")
    ) into (
        reads_tumor_hla_ch,
        reads_tumor_hlaHD_ch
    )

    script:
    mhc_region = params.HLA_HD_genome_version ? params.MHC_genomic_region[ params.HLA_HD_genome_version ].region ?: false : false

    if (!mhc_region) {
        exit 1, "MHC region not found for genome version: ${params.HLA_HD_genome_version}"
    }

    mhcReads_1 = (single_end) ? TumorReplicateId + "_reads_mhc.fastq.gz" : TumorReplicateId + "_reads_mhc_R1.fastq.gz"
    mhcReads_2 = (single_end) ? "NO_FILE" : TumorReplicateId + "_reads_mhc_R2.fastq.gz"

    if(single_end)
        """
        rm -f unmapped_bam mhc_mapped_bam R.fastq
        mkfifo unmapped_bam
        mkfifo mhc_mapped_bam
        mkfifo R.fastq

        samtools  view -@4 -h -b -u -f 4 ${tumor_BAM_aligned_sort_mkdp} > unmapped_bam &
        samtools  view -@4 -h -b -u ${tumor_BAM_aligned_sort_mkdp} ${mhc_region} > mhc_mapped_bam &

        samtools merge -@4 -u - mhc_mapped_bam unmapped_bam | \\
            samtools sort -@4 -n - | \\
            samtools fastq -@2 -0 R.fastq - &
        perl -ple 'if ((\$. % 4) == 1) { s/\$/ 1:N:0:NNNNNNNN/; }' R.fastq | gzip -1 > ${TumorReplicateId}_reads_mhc.fastq.gz

        wait
        touch NO_FILE

        rm -f unmapped_bam mhc_mapped_bam R.fastq
        """
    else
        """
        rm -f unmapped_bam mhc_mapped_bam R1.fastq R2.fastq
        mkfifo unmapped_bam
        mkfifo mhc_mapped_bam
        mkfifo R1.fastq
        mkfifo R2.fastq

        samtools  view -@4 -h -b -u -f 4 ${tumor_BAM_aligned_sort_mkdp} > unmapped_bam &
        samtools  view -@4 -h -b -u ${tumor_BAM_aligned_sort_mkdp} ${mhc_region} > mhc_mapped_bam &

        samtools merge -@4 -u - mhc_mapped_bam unmapped_bam | \\
            samtools sort -@4 -n - | \\
            samtools fastq -@2 -1 R1.fastq -2 R2.fastq -s /dev/null -0 /dev/null - &
        perl -ple 'if ((\$. % 4) == 1) { s/\$/ 1:N:0:NNNNNNNN/; }' R1.fastq | gzip -1 > ${TumorReplicateId}_reads_mhc_R1.fastq.gz &
        perl -ple 'if ((\$. % 4) == 1) { s/\$/ 2:N:0:NNNNNNNN/; }' R2.fastq | gzip -1 > ${TumorReplicateId}_reads_mhc_R2.fastq.gz &

        wait

        rm -f unmapped_bam mhc_mapped_bam R1.fastq R2.fastq
        """
}

/*
*********************************************
**             O P T I T Y P E             **
*********************************************
*/

/*
 * Preparation Step - Pre-mapping against HLA
 *
 * In order to avoid the internal usage of RazerS from within OptiType when
 * the input files are of type `fastq`, we perform a pre-mapping step
 * here with the `yara` mapper, and map against the HLA reference only.
 *
 */

if (run_OptiType) {

    process 'pre_map_hla' {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/10_HLA_typing/Optitype/processing/",
            mode: params.publishDirMode,
            enabled: params.fullOutput

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(readsFWD),
            file(readsREV),
        ) from reads_tumor_hla_ch

        file yaraIdx_files from Channel.value(reference.YaraIndexDNA)
        val yaraIdx from Channel.value(reference.YaraIndexDNA[0].simpleName)

        output:
        set (
            TumorReplicateId,
            file("dna_mapped_{1,2}.bam")
        ) into fished_reads

        script:
        if(single_end) {
            yara_cpus = ((task.cpus - 2).compareTo(2) == -1) ? 2 : (task.cpus - 2)
            samtools_cpus = ((task.cpus - yara_cpus).compareTo(1) == -1) ? 1 : (task.cpus - yara_cpus)
        } else {
            yara_cpus = ((task.cpus - 6).compareTo(2) == -1) ? 2 : (task.cpus - 6)
            samtools_cpus =  (((task.cpus - yara_cpus).div(3)).compareTo(1) == -1) ? 1 : (task.cpus - yara_cpus).div(3)
        }

        if (single_end)
            """
            yara_mapper -e 3 -t $yara_cpus -f bam ${yaraIdx} ${readsFWD} | \\
                samtools view -@ $samtools_cpus -h -F 4 -b1 -o dna_mapped_1.bam
            """
        else
            """
            rm -f R1 R2
            mkfifo R1 R2
            yara_mapper -e 3 -t $yara_cpus -f bam ${yaraIdx} ${readsFWD} ${readsREV} | \\
                samtools view -@ $samtools_cpus -h -F 4 -b1 | \\
                tee R1 R2 > /dev/null &
                samtools view -@ $samtools_cpus -h -f 0x40 -b1 R1 > dna_mapped_1.bam &
                samtools view -@ $samtools_cpus -h -f 0x80 -b1 R2 > dna_mapped_2.bam &
            wait
            rm -f R1 R2
            """
    }

    /*
    * STEP 2 - Run Optitype
    *
    * This is the major process, that formulates the IP and calls the selected
    * IP solver.
    *
    * Ouput formats: <still to enter>
    */

    process 'OptiType' {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/10_HLA_typing/Optitype/",
            mode: params.publishDirMode

        input:
        set (
            TumorReplicateId,
            file(reads)
        ) from fished_reads

        output:
        set (
            TumorReplicateId,
            file("${TumorReplicateId}_optitype_result.tsv")
        ) into optitype_output
        file("${TumorReplicateId}_optitype_coverage_plot.pdf")

        script:
        """
        OPTITYPE="\$(readlink -f \$(which OptiTypePipeline.py))"
        \$OPTITYPE -i ${reads} -e 1 -b 0.009 --dna -o ./tmp && \\
        mv ./tmp/*/*_result.tsv ./${TumorReplicateId}_optitype_result.tsv && \\
        mv ./tmp/*/*_coverage_plot.pdf ./${TumorReplicateId}_optitype_coverage_plot.pdf && \\
        rm -rf ./tmp/
        """
    }

    if (have_RNAseq && ! have_RNA_tag_seq) {
        process 'pre_map_hla_RNA' {

            label 'nextNEOpiENV'

            tag "$TumorReplicateId"

            publishDir "$params.outputDir/analyses/$TumorReplicateId/10_HLA_typing/Optitype/processing/",
                mode: params.publishDirMode,
                enabled: params.fullOutput

            input:
            set(
                TumorReplicateId,
                NormalReplicateId,
                file(readRNAFWD),
                file(readRNAREV)
            ) from reads_tumor_optitype_ch

            file yaraIdx_files from Channel.value(reference.YaraIndexRNA)
            val yaraIdx from Channel.value(reference.YaraIndexRNA[0].simpleName)

            output:
            set (
                TumorReplicateId,
                file("rna_mapped_{1,2}.bam")
            ) into fished_reads_RNA

            script:
            if(single_end) {
                yara_cpus = ((task.cpus - 2).compareTo(2) == -1) ? 2 : (task.cpus - 2)
                samtools_cpus = ((task.cpus - yara_cpus).compareTo(1) == -1) ? 1 : (task.cpus - yara_cpus)
            } else {
                yara_cpus = ((task.cpus - 6).compareTo(2) == -1) ? 2 : (task.cpus - 6)
                samtools_cpus =  (((task.cpus - yara_cpus).div(3)).compareTo(1) == -1) ? 1 : (task.cpus - yara_cpus).div(3)
            }

            if (single_end_RNA)
                """
                yara_mapper -e 3 -t $yara_cpus -f bam ${yaraIdx} ${readRNAFWD} | \\
                    samtools view -@ $samtools_cpus -h -F 4 -b1 -o rna_mapped_1.bam
                """
            else
                """
                rm -f R1 R2
                mkfifo R1 R2
                yara_mapper -e 3 -t $yara_cpus -f bam ${yaraIdx} ${readRNAFWD} ${readRNAREV} | \\
                    samtools view -@ $samtools_cpus -h -F 4 -b1 | \\
                    tee R1 R2 > /dev/null &
                    samtools view -@ $samtools_cpus -h -f 0x40 -b1 R1 > rna_mapped_1.bam &
                    samtools view -@ $samtools_cpus -h -f 0x80 -b1 R2 > rna_mapped_2.bam &
                wait
                rm -f R1 R2
                """
        }

        process 'OptiType_RNA' {

            label 'nextNEOpiENV'

            tag "$TumorReplicateId"

            publishDir "$params.outputDir/analyses/$TumorReplicateId/10_HLA_typing/Optitype/",
                mode: params.publishDirMode

            input:
            set (
                TumorReplicateId,
                file(reads)
            ) from fished_reads_RNA

            output:
            set (
                TumorReplicateId,
                file("${TumorReplicateId}_optitype_RNA_result.tsv")
            ) into optitype_RNA_output
            file("${TumorReplicateId}_optitype_RNA_coverage_plot.pdf")

            script:
            if (single_end_RNA)
                """
                OPTITYPE="\$(readlink -f \$(which OptiTypePipeline.py))"
                MHC_MAPPED=`samtools view -c ${reads}`
                if [ "\$MHC_MAPPED" != "0" ]; then
                    \$OPTITYPE -i ${reads} -e 1 -b 0.009 --rna -o ./tmp && \\
                    mv ./tmp/*/*_result.tsv ./${TumorReplicateId}_optitype_RNA_result.tsv && \\
                    mv ./tmp/*/*_coverage_plot.pdf ./${TumorReplicateId}_optitype_RNA_coverage_plot.pdf && \\
                    rm -rf ./tmp/
                else
                    touch ${TumorReplicateId}_optitype_RNA_result.tsv
                    echo "No result" >  ${TumorReplicateId}_optitype_RNA_coverage_plot.pdf
                fi
                """
            else
                """
                OPTITYPE="\$(readlink -f \$(which OptiTypePipeline.py))"
                MHC_MAPPED_FWD=`samtools view -c ${reads[0]}`
                MHC_MAPPED_REV=`samtools view -c ${reads[1]}`
                if [ "\$MHC_MAPPED_FWD" != "0" ] || [ "\$MHC_MAPPED_REV" != "0" ]; then
                    \$OPTITYPE -i ${reads} -e 1 -b 0.009 --rna -o ./tmp && \\
                    mv ./tmp/*/*_result.tsv ./${TumorReplicateId}_optitype_RNA_result.tsv && \\
                    mv ./tmp/*/*_coverage_plot.pdf ./${TumorReplicateId}_optitype_RNA_coverage_plot.pdf && \\
                    rm -rf ./tmp/
                else
                    touch ${TumorReplicateId}_optitype_RNA_result.tsv
                    echo "No result" > ${TumorReplicateId}_optitype_RNA_coverage_plot.pdf
                fi
                """
        }

    } else if (have_RNAseq && have_RNA_tag_seq) {

        log.info "INFO: will not run HLA typing on RNAseq from tag libraries"

        optitype_RNA_output = reads_tumor_optitype_ch
                                .map{ it -> tuple(it[0], file("NO_FILE_OPTI_RNA"))}

    }
}  else { // End if run_OptiType
    log.info "INFO: will not run HLA typing with OptiType"

    optitype_output = reads_tumor_hla_ch
                            .map{ it -> tuple(it[0], file("NO_FILE_OPTI_DNA"))}

    if (have_RNAseq) {
        optitype_RNA_output = reads_tumor_optitype_ch
                                .map{ it -> tuple(it[0], file("NO_FILE_OPTI_RNA"))}
    }
}

/*
*********************************************
**             H L A - H D                 **
*********************************************
*/

if (have_HLAHD) {
    process 'run_hla_hd' {

        label 'HLAHD'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/10_HLA_typing/HLA_HD/",
            saveAs: { fileName -> fileName.endsWith("_final.result.txt") ? file(fileName).getName() : null },
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(readsFWD),
            file(readsREV)
        ) from reads_tumor_hlaHD_ch

        file frData from Channel.value(reference.HLAHDFreqData)
        file gSplit from Channel.value(reference.HLAHDGeneSplit)
        file dict from Channel.value(reference.HLAHDDict)

        output:
        set (
            TumorReplicateId,
            file("**/*_final.result.txt")
        ) into (
            hlahd_output,
            hlahd_mixMHC2_pred_ch0
        )

        script:
        hlahd_p = Channel.value(HLAHD_PATH).getVal()

        if (single_end)
            """
            export PATH=\$PATH:$hlahd_p
            $HLAHD -t ${task.cpus} \\
                -m 50 \\
                -f ${frData} ${readsFWD} ${readsFWD} \\
                ${gSplit} ${dict} $TumorReplicateId .
            """
        else
            """
            export PATH=\$PATH:$hlahd_p
            $HLAHD -t ${task.cpus} \\
                -m 50 \\
                -f ${frData} ${readsFWD} ${readsREV} \\
                ${gSplit} ${dict} $TumorReplicateId .
            """
    }
} else {
    // fill channels
    hlahd_output = reads_tumor_hlaHD_ch
                        .map{ it -> tuple(it[0], file("NO_FILE_HLAHD_DNA"))}

    (hlahd_mixMHC2_pred_ch0, hlahd_output) = hlahd_output.into(2)

}

if (have_RNAseq && have_HLAHD && ! have_RNA_tag_seq && params.run_HLAHD_RNA) {
    process 'run_hla_hd_RNA' {

        label 'HLAHD_RNA'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/10_HLA_typing/HLA_HD/",
            saveAs: { fileName -> fileName.endsWith("_final.result.txt") ? file(fileName).getName().replace(".txt", ".RNA.txt") : null },
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(readsFWD),
            file(readsREV)
        ) from reads_tumor_hlahd_RNA_ch

        file frData from Channel.value(reference.HLAHDFreqData)
        file gSplit from Channel.value(reference.HLAHDGeneSplit)
        file dict from Channel.value(reference.HLAHDDict)

        output:
        set (
            TumorReplicateId,
            file("**/*_final.result.txt")
        ) into (
            hlahd_output_RNA
        )

        script:
        hlahd_p = Channel.value(HLAHD_PATH).getVal()

        if (single_end_RNA)
            """
            export PATH=\$PATH:$hlahd_p
            $HLAHD -t ${task.cpus} \\
                -m 50 \\
                -f ${frData} ${readsFWD} ${readsFWD} \\
                ${gSplit} ${dict} $TumorReplicateId .
            """
        else
            """
            export PATH=\$PATH:$hlahd_p
            $HLAHD -t ${task.cpus} \\
                -m 50 \\
                -f ${frData} ${readsFWD} ${readsREV} \\
                ${gSplit} ${dict} $TumorReplicateId .
            """
    }
} else if ((have_RNAseq && ! have_HLAHD) || (have_RNAseq && have_RNA_tag_seq) || (! params.run_HLAHD_RNA)) {

    if(have_RNA_tag_seq) {
        log.info "INFO: will not run HLA typing on RNAseq from tag libraries"
    }

    hlahd_output_RNA = reads_tumor_hlahd_RNA_ch
                            .map{ it -> tuple(it[0], file("NO_FILE_HLAHD_RNA"))}

}

/*
Get the HLA types from OptiType and HLA-HD ouput as a "\n" seperated list.
To be used as input for pVACseq

From slack discussion on 20200425 (FF, GF, DR):

    * We run Optitype RNA and WES in the main pipeline (only on tumor)
    * We consider the WES class I HLA
    * IFF the WES-based HLA are homo and are a subset of RNA-based HLA, then we consider also the second HLA alleles predicted from RNA
    * These class I HLA are used for the somatic pipeline and also for the embedded NeoFuse
*/

process get_vhla {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/neoantigens/$TumorReplicateId/Final_HLAcalls/",
    mode: params.publishDirMode

    input:
    set (
        TumorReplicateId,
        file(opti_out),
        file(opti_out_rna),
        file(hlahd_out),
        file(hlahd_out_rna),
        file(custom_hlas)
    ) from optitype_output
        .combine(optitype_RNA_output, by: 0)
        .combine(hlahd_output, by: 0)
        .combine(hlahd_output_RNA, by: 0)
        .combine(custom_hlas_ch, by: 0)

    output:
    set (
        TumorReplicateId,
        file("${TumorReplicateId}_hlas.txt")
    ) into (hlas, hlas_neoFuse)

    script:
    def optitype_hlas = (opti_out.name != 'NO_FILE_OPTI_DNA') ? "--opti_out $opti_out" : ''
    def user_hlas = custom_hlas.name != 'NO_FILE_HLA' ? "--custom $custom_hlas" : ''
    def rna_hlas = (have_RNAseq && ! have_RNA_tag_seq && (opti_out_rna.name != 'NO_FILE_OPTI_RNA')) ? "--opti_out_RNA $opti_out_rna" : ''
    rna_hlas = (have_RNAseq && have_HLAHD && ! have_RNA_tag_seq && params.run_HLAHD_RNA) ? rna_hlas + " --hlahd_out_RNA $hlahd_out_rna" : rna_hlas
    def force_seq_type = ""

    def force_RNA = (params.HLA_force_DNA || have_RNA_tag_seq) ? false : params.HLA_force_RNA

    if(force_RNA && ! have_RNAseq) {
        log.warn "WARNING: Can not force RNA data for HLA typing: no RNAseq data provided!"
    } else if (force_RNA && have_RNAseq) {
        force_seq_type = "--force_RNA"
    } else if (params.HLA_force_DNA) {
        force_seq_type = "--force_DNA"
    }

    hlahd_opt = (have_HLAHD && (hlahd_out.name != 'NO_FILE_HLAHD_DNA')) ? "--hlahd_out ${hlahd_out}" : ""

    script:
    pVACseqAlleles = baseDir.toRealPath()  + "/assets/pVACseqAlleles.txt"
    """
    # merging script
    HLA_parser.py \\
        ${optitype_hlas} \\
        ${hlahd_opt} \\
        ${rna_hlas} \\
        ${user_hlas} \\
        ${force_seq_type} \\
        --ref_hlas ${pVACseqAlleles} \\
        > ./${TumorReplicateId}_hlas.txt
    """
}

// END HLA TYPING

// NeoAntigen predictions

/*
*********************************************
**      N E O F U S E / P V A C S E Q      **
*********************************************
*/

/*
Prediction of gene fusion neoantigens with Neofuse and calculation of TPM values
*/

if (have_RNAseq) {
    process Neofuse {

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/",
            saveAs: {
                fileName ->
                    if(fileName.indexOf("Arriba") >= 0) {
                        targetFile = "11_Fusions/Arriba/" + file(fileName).getName()
                    } else if(fileName.indexOf("Custom_HLAs") >= 0) {
                        targetFile = params.fullOutput ? "11_Fusions/Custom_HLAs/" + file(fileName).getName() : ""
                    } else if(fileName.indexOf("LOGS/") >= 0) {
                        targetFile = params.fullOutput ? "11_Fusions/LOGS/" + file(fileName).getName() : ""
                    } else if(fileName.indexOf("NeoFuse/MHC_I/") >= 0) {
                        targetFile = "11_Fusions/NeoFuse/" + file(fileName).getName().replace("_unsupported.txt", "_MHC_I_unsupported.txt")
                    } else if(fileName.indexOf("NeoFuse/MHC_II/") >= 0) {
                        if(fileName.indexOf("_mixMHC2pred_conf.txt") < 0) {
                            targetFile = "11_Fusions/NeoFuse/" + file(fileName).getName().replace("_unsupported.txt", "_MHC_II_unsupported.txt")
                        } else {
                            targetFile = params.fullOutput ? "11_Fusions/NeoFuse/" + file(fileName).getName() : ""
                        }
                    } else if(fileName.indexOf("STAR/") >= 0) {
                        if(fileName.indexOf("Aligned.sortedByCoord.out.bam") >= 0) {
                            targetFile = "02_alignments/" + file(fileName).getName().replace(".Aligned.sortedByCoord.out", "_RNA.Aligned.sortedByCoord.out")
                        }
                    } else if(fileName.indexOf("TPM/") >= 0) {
                        targetFile = "04_expression/" + file(fileName).getName()
                    } else {
                        targetFile = "11_Fusions/" + fileName
                    }
                    return "$targetFile"
            },
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(readRNAFWD),
            file(readRNAREV),
            file(hla_types),
            _,
            file(SVvcf),
            file(SVvcfIdx)
        ) from reads_tumor_neofuse_ch
            .combine(hlas_neoFuse, by: 0)
            .combine(MantaSomaticIndels_out_NeoFuse_in_ch0, by: 0)

        file STARidx from file(reference.STARidx)
        file RefFasta from file(reference.RefFasta)
        file AnnoFile from file(reference.AnnoFile)

        output:
        set (
            TumorReplicateId,
            file("./${TumorReplicateId}/NeoFuse/MHC_I/${TumorReplicateId}_MHCI_filtered.tsv"),
            file("./${TumorReplicateId}/NeoFuse/MHC_I/${TumorReplicateId}_MHCI_unfiltered.tsv"),
            file("./${TumorReplicateId}/NeoFuse/MHC_II/${TumorReplicateId}_MHCII_filtered.tsv"),
            file("./${TumorReplicateId}/NeoFuse/MHC_II/${TumorReplicateId}_MHCII_unfiltered.tsv")
        ) into Neofuse_results
        set (
            TumorReplicateId,
            file("./${TumorReplicateId}/TPM/${TumorReplicateId}.tpm.txt")
        ) into tpm_file
        set (
            TumorReplicateId,
            file("./${TumorReplicateId}/STAR/${TumorReplicateId}.Aligned.sortedByCoord.out.bam"),
            file("./${TumorReplicateId}/STAR/${TumorReplicateId}.Aligned.sortedByCoord.out.bam.bai")
        ) into star_bam_file
        path("${TumorReplicateId}/**")


        script:
        sv_options = (single_end) ? "" : "-v ${SVvcf}"
        if(single_end_RNA)
            """
            NeoFuse_single -1 ${readRNAFWD} \\
                -d ${TumorReplicateId} \\
                -o . \\
                -m ${params.pepMin_length} \\
                -M ${params.pepMax_length} \\
                -n ${task.cpus} \\
                -t ${params.IC50_Threshold} \\
                -T ${params.rank} \\
                -c ${params.conf_lvl} \\
                -s ${STARidx} \\
                -g ${RefFasta} \\
                -a ${AnnoFile} \\
                -N ${params.netMHCpan} \\
                -C ${hla_types} \\
                ${sv_options} \\
                -k true
            """
        else
            """
            NeoFuse_single -1 ${readRNAFWD} -2 ${readRNAREV} \\
                -d ${TumorReplicateId} \\
                -o . \\
                -m ${params.pepMin_length} \\
                -M ${params.pepMax_length} \\
                -n ${task.cpus} \\
                -t ${params.IC50_Threshold} \\
                -T ${params.rank} \\
                -c ${params.conf_lvl} \\
                -s ${STARidx} \\
                -g ${RefFasta} \\
                -a ${AnnoFile} \\
                -N ${params.netMHCpan} \\
                -C ${hla_types} \\
                ${sv_options} \\
                -k true
            """
    }

    process publish_NeoFuse {
        tag "$TumorReplicateId"

        publishDir "$params.outputDir/neoantigens/$TumorReplicateId/",
        saveAs: {
            fileName ->
                if(fileName.indexOf("_MHCI_") >= 0) {
                    targetFile = "Class_I/Fusions/" + fileName.replace("${TumorReplicateId}", "${TumorReplicateId}_NeoFuse")
                } else if(fileName.indexOf("_MHCII_") >= 0) {
                    targetFile = "Class_II/Fusions/" + fileName.replace("${TumorReplicateId}", "${TumorReplicateId}_NeoFuse")
                } else {
                    targetFile = fileName
                }
                return targetFile
        },
        mode: "copy"

        input:
        set(
            TumorReplicateId,
            file(MHC_I_filtered),
            file(MHC_I_unfiltered),
            file(MHC_II_filtered),
            file(MHC_II_unfiltered)
        ) from Neofuse_results

        output:
        file(MHC_I_filtered)
        file(MHC_I_unfiltered)
        file(MHC_II_filtered)
        file(MHC_II_unfiltered)

        script:
        """
        echo "Done"
        """
    }

    /*
    Add the gene ID (required by vcf-expression-annotator) to the TPM file
    */
    process add_geneID {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        input:
        set (
            TumorReplicateId,
            file(tpm)
        ) from tpm_file
        // file tpm from tpm_file
        file AnnoFile from file(reference.AnnoFile)

        output:
        set (
            TumorReplicateId,
            file("*.tpm_final.txt")
        ) into final_file

        script:
        """
        NameToID.py -i ${tpm} -a ${AnnoFile} -o .
        """
    }

    /*
    Add gene expression info to the VEP annotated, phased VCF file
    */

    process gene_annotator {

        tag "$TumorReplicateId"

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(vep_somatic_vcf_gz),
            file(vep_somatic_vcf_gz_tbi),
            file(final_tpm),
            file(RNA_bam),
            file(RNA_bai),
        ) from VEPvcf_out_ch2
            .combine(final_file, by: 0)
            .combine(star_bam_file, by: 0)
        set(
            file(RefFasta),
            file(RefIdx),
        ) from Channel.value(
            [ reference.RefFasta,
            reference.RefIdx ]
        )

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${TumorReplicateId}_vep_somatic_gx.vcf.gz"),
            file("${TumorReplicateId}_vep_somatic_gx.vcf.gz.tbi")
        ) into (
            vcf_vep_ex_gz,
            gene_annotator_out_mixMHC2pred_ch0,
            generate_protein_fasta_tumor_vcf_ch0
        )

        script:
        """
        vcf-expression-annotator \\
            -i GeneID \\
            -e TPM \\
            -s ${TumorReplicateId} \\
            ${vep_somatic_vcf_gz} ${final_tpm} \\
            custom gene \\
            -o ./${TumorReplicateId}_vep_somatic_gx_tmp.vcf
        bgzip -f ${TumorReplicateId}_vep_somatic_gx_tmp.vcf
        tabix -p vcf ${TumorReplicateId}_vep_somatic_gx_tmp.vcf.gz

        vt decompose \\
            -s ${TumorReplicateId}_vep_somatic_gx_tmp.vcf.gz \\
            -o ${TumorReplicateId}_vep_somatic_gx_dec_tmp.vcf.gz

        bam_readcount_helper.py \\
            ${TumorReplicateId}_vep_somatic_gx_dec_tmp.vcf.gz \\
            ${TumorReplicateId} \\
            ${RefFasta} \\
            ${RNA_bam} \\
            ./

        vcf-readcount-annotator \\
            -s ${TumorReplicateId} \\
            -t snv \\
            -o ${TumorReplicateId}_vep_somatic_gx_dec_snv_rc_tmp.vcf \\
            ${TumorReplicateId}_vep_somatic_gx_dec_tmp.vcf.gz \\
            ${TumorReplicateId}_bam_readcount_snv.tsv \\
            RNA

        vcf-readcount-annotator \\
            -s ${TumorReplicateId} \\
            -t indel \\
            -o ${TumorReplicateId}_vep_somatic_gx.vcf \\
            ${TumorReplicateId}_vep_somatic_gx_dec_snv_rc_tmp.vcf \\
            ${TumorReplicateId}_bam_readcount_indel.tsv \\
            RNA

        bgzip -f ${TumorReplicateId}_vep_somatic_gx.vcf
        tabix -p vcf ${TumorReplicateId}_vep_somatic_gx.vcf.gz
        """
    }
} else { // no RNAseq data

    (vcf_vep_ex_gz,  gene_annotator_out_mixMHC2pred_ch0, generate_protein_fasta_tumor_vcf_ch0) = VEPvcf_out_ch2.into(3)

}

/*
Run pVACseq
*/

process 'pVACseq' {

    tag "$TumorReplicateId"

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(vep_phased_vcf_gz),
        file(vep_phased_vcf_gz_tbi),
        file(anno_vcf),
        file(anno_vcf_tbi),
        val(hla_types)
    ) from mkPhasedVCF_out_pVACseq_ch0
        .combine(vcf_vep_ex_gz, by: [0,1])
        .combine(hlas.splitText(), by: 0)

    output:
    set(
        TumorReplicateId,
        file("**/MHC_Class_I/*filtered.tsv"),
        file("**/MHC_Class_I/*all_epitopes.tsv")
    ) optional true into mhcI_out_f

    set(
        TumorReplicateId,
        file("**/MHC_Class_II/*filtered.tsv"),
        file("**/MHC_Class_II/*all_epitopes.tsv")
    ) optional true into mhcII_out_f


    script:
    hla_type = (hla_types - ~/\n/)
    NetChop = params.use_NetChop ? "--net-chop-method cterm" : ""
    NetMHCstab = params.use_NetMHCstab ? "--netmhc-stab" : ""
    phased_vcf_opt = (have_GATK3) ? "-p " + vep_phased_vcf_gz : ""

    filter_set = params.pVACseq_filter_sets[ "standard" ]

    if (params.pVACseq_filter_sets[ params.pVACseq_filter_set ] != null) {
        filter_set = params.pVACseq_filter_sets[ params.pVACseq_filter_set ]
    } else {
        log.warn "WARNING: pVACseq_filter_set must be one of: standard, relaxed, custom\n" +
            "using standard"
        filter_set = params.pVACseq_filter_sets[ "standard" ]
    }


    if(!have_GATK3) {

        log.warn "WARNING: GATK3 not installed! Have no readbacked phased VCF:\n" +
            "You should manually review the sequence data for all candidates (e.g. in IGV) for proximal variants and\n" +
            " either account for these manually, or eliminate these candidates. Failure to do so may lead to inclusion\n" +
            " of incorrect peptide sequences."

    }

    if (have_RNA_tag_seq) {
        filter_set = filter_set.replaceAll(/--trna-vaf\s+\d+\.{0,1}\d*/, "--trna-vaf 0.0")
        filter_set = filter_set.replaceAll(/--trna-cov\s+\d+/, "--trna-cov 0")
    }

    """
    pvacseq run \\
        --iedb-install-directory /opt/iedb \\
        -t ${task.cpus} \\
        ${phased_vcf_opt} \\
        -e1 ${params.mhci_epitope_len} \\
        -e2 ${params.mhcii_epitope_len} \\
        --normal-sample-name ${NormalReplicateId} \\
        ${NetChop} \\
        ${NetMHCstab} \\
        ${filter_set} \\
        ${anno_vcf} ${TumorReplicateId} ${hla_type} ${params.epitope_prediction_tools} ./${TumorReplicateId}_${hla_type}
    """
}

process concat_mhcI_files {

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/12_pVACseq/MHC_Class_I/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        file("*filtered.tsv"),
        file("*all_epitopes.tsv")
    ) from mhcI_out_f.groupTuple(by: 0)

    output:
    set(
        TumorReplicateId,
        file("${TumorReplicateId}_MHCI_filtered.tsv")
    ) into (
        MHCI_final_immunogenicity,
        concat_mhcI_filtered_files_out_addCCF_ch0
    )
    set(
        TumorReplicateId,
        file("${TumorReplicateId}_MHCI_all_epitopes.tsv")
    ) into (
        MHCI_all_epitopes,
        concat_mhcI_all_files_out_aggregated_reports_ch0,
        concat_mhcI_all_files_out_addCCF_ch0
    )

    script:
    """
    sed -e '2,\${/^Chromosome/d' -e '}' *filtered.tsv > ${TumorReplicateId}_MHCI_filtered.tsv
    sed -e '2,\${/^Chromosome/d' -e '}' *all_epitopes.tsv > ${TumorReplicateId}_MHCI_all_epitopes.tsv
    """
}

process concat_mhcII_files {

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/12_pVACseq/MHC_Class_II/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        file("*filtered.tsv"),
        file("*all_epitopes.tsv")
    ) from mhcII_out_f.groupTuple(by: 0)

    output:
    set(
        TumorReplicateId,
        file("${TumorReplicateId}_MHCII_filtered.tsv")
    ) into (
        concat_mhcII_filtered_files_out_addCCF_ch0
    )
    set(
        TumorReplicateId,
        file("${TumorReplicateId}_MHCII_all_epitopes.tsv")
    ) into (
        MHCII_all_epitopes,
        concat_mhcII_all_files_out_aggregated_reports_ch0,
        concat_mhcII_all_files_out_addCCF_ch0
    )

    script:
    """
    sed -e '2,\${/^Chromosome/d' -e '}' *filtered.tsv > ${TumorReplicateId}_MHCII_filtered.tsv
    sed -e '2,\${/^Chromosome/d' -e '}' *all_epitopes.tsv > ${TumorReplicateId}_MHCII_all_epitopes.tsv
    """
}


process aggregated_reports {

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/12_pVACseq/",
        mode: params.publishDirMode

    input:
    set (
        TumorReplicateId,
        file(pvacseq_mhcI_all_file),
        file(pvacseq_mhcII_all_file)
    ) from concat_mhcI_all_files_out_aggregated_reports_ch0
        .combine(concat_mhcII_all_files_out_aggregated_reports_ch0, by: 0)


    output:
    file("**/*_MHCI_all_aggregated.tsv")
    file("**/*_MHCII_all_aggregated.tsv")

    script:
    """
    mkdir ./MHC_Class_I/
    pvacseq generate_aggregated_report \\
        $pvacseq_mhcI_all_file \\
        ./MHC_Class_I/${TumorReplicateId}_MHCI_all_aggregated.tsv
    mkdir ./MHC_Class_II/
    pvacseq generate_aggregated_report \\
        $pvacseq_mhcII_all_file \\
        ./MHC_Class_II/${TumorReplicateId}_MHCII_all_aggregated.tsv
    """
}

process 'pVACtools_generate_protein_seq' {

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/06_proteinseq/",
    mode: params.publishDirMode,
    enabled: params.fullOutput

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file(vep_phased_vcf_gz),
        file(vep_phased_vcf_idx),
        file(vep_tumor_vcf_gz),
        file(vep_tumor_vcf_idx)
    ) from generate_protein_fasta_phased_vcf_ch0
        .combine(generate_protein_fasta_tumor_vcf_ch0, by:[0,1])

    output:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("${TumorReplicateId}_long_peptideSeq.fasta")
    ) optional true into pVACtools_generate_protein_seq

    script:
    phased_vcf_opt = (have_GATK3) ? "-p " + vep_phased_vcf_gz : ""

    if(!have_GATK3) {

        log.warn "WARNING: GATK3 not installed! Have no readbacked phased VCF:\n" +
        "You should manually review the sequence data for all candidates (e.g. in IGV) for proximal variants and\n" +
        " either account for these manually, or eliminate these candidates. Failure to do so may lead to inclusion\n" +
        " of incorrect peptide sequences."
    }

    """
    pvacseq generate_protein_fasta \\
        ${phased_vcf_opt} \\
        -s ${TumorReplicateId} \\
        ${vep_tumor_vcf_gz} \\
        31 \\
        ${TumorReplicateId}_long_peptideSeq.fasta
    """
}

if(have_HLAHD) {
    process 'pepare_mixMHC2_seq' {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/$TumorReplicateId/13_mixMHC2pred/processing/",
            mode: params.publishDirMode,
            enabled: params.fullOutput

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(long_peptideSeq_fasta),
            file(hlahd_allel_file)
        ) from pVACtools_generate_protein_seq
            .combine(hlahd_mixMHC2_pred_ch0, by:0)

        output:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file("${TumorReplicateId}_peptides.fasta")
        ) optional true into pepare_mixMHC2_seq_out_ch0
        file("${TumorReplicateId}_mixMHC2pred.txt") optional true into pepare_mixMHC2_seq_out_ch1
        file("${TumorReplicateId}_unsupported.txt") optional true
        file("${TumorReplicateId}_mixMHC2pred_conf.txt") optional true

        script:
        supported_list = baseDir.toRealPath() + "/assets/hlaii_supported.txt"
        model_list     = baseDir.toRealPath() + "/assets/hlaii_models.txt"
        """
        pepChopper.py \\
            --pep_len ${params.mhcii_epitope_len.split(",").join(" ")} \\
            --fasta_in ${long_peptideSeq_fasta} \\
            --fasta_out ${TumorReplicateId}_peptides.fasta
        HLAHD2mixMHC2pred.py \\
            --hlahd_list ${hlahd_allel_file} \\
            --supported_list ${supported_list} \\
            --model_list ${model_list} \\
            --output_dir ./ \\
            --sample_name ${TumorReplicateId}
        """
    }

    mixmhc2pred_chck_file = file(workflow.workDir + "/.mixmhc2pred_install_ok.chck")
    mixmhc2pred_target = workflow.workDir + "/MixMHC2pred"
    if(( ! mixmhc2pred_chck_file.exists() || mixmhc2pred_chck_file.isEmpty()) && params.MiXMHC2PRED == "") {
        process install_mixMHC2pred {

            tag 'install mixMHC2pred'

            // do not cache
            cache false

            output:
            file(".mixmhc2pred_install_ok.chck") into mixmhc2pred_chck_ch

            script:
            """
            curl -sLk ${params.MiXMHC2PRED_url} -o mixmhc2pred.zip && \\
            unzip mixmhc2pred.zip -d ${mixmhc2pred_target} && \\
            echo "OK" > .mixmhc2pred_install_ok.chck && \\
            cp -f .mixmhc2pred_install_ok.chck ${mixmhc2pred_chck_file}
            """
        }
    } else if (( ! mixmhc2pred_chck_file.exists() || mixmhc2pred_chck_file.isEmpty()) && params.MiXMHC2PRED != "") {
        process link_mixMHC2pred {

            tag 'link mixMHC2pred'

            // do not cache
            cache false

            output:
            file(".mixmhc2pred_install_ok.chck") into mixmhc2pred_chck_ch

            script:
            """
            ln -s ${params.MiXMHC2PRED} ${mixmhc2pred_target} && \\
            echo "OK" > .mixmhc2pred_install_ok.chck && \\
            cp -f .mixmhc2pred_install_ok.chck ${mixmhc2pred_chck_file}
            """
        }
    } else {
        mixmhc2pred_chck_ch = Channel.fromPath(mixmhc2pred_chck_file)
    }

    process mixMHC2pred {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/13_mixMHC2pred",
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(mut_peps),
            file(vep_somatic_gx_vcf_gz),
            file(vep_somatic_gx_vcf_gz_tbi),
            file(mixmhc2pred_chck_file)
        ) from pepare_mixMHC2_seq_out_ch0
            .combine(gene_annotator_out_mixMHC2pred_ch0, by: [0, 1])
            .combine(mixmhc2pred_chck_ch)
        val allelesFile from pepare_mixMHC2_seq_out_ch1

        output:
        file("${TumorReplicateId}_mixMHC2pred_all.tsv") optional true
        file("${TumorReplicateId}_mixMHC2pred_filtered.tsv") optional true

        script:
        alleles = file(allelesFile).readLines().join(" ")

        if(alleles.length() > 0)
            """
            ${mixmhc2pred_target}/MixMHC2pred_unix \\
                -i ${mut_peps} \\
                -o ${TumorReplicateId}_mixMHC2pred.tsv \\
                -a ${alleles}
            parse_mixMHC2pred.py \\
                --vep_vcf ${vep_somatic_gx_vcf_gz} \\
                --pep_fasta ${mut_peps} \\
                --mixMHC2pred_result ${TumorReplicateId}_mixMHC2pred.tsv \\
                --out ${TumorReplicateId}_mixMHC2pred_all.tsv \\
                --sample_name ${TumorReplicateId} \\
                --normal_name ${NormalReplicateId}
            awk \\
                '{
                    if (\$0 ~ /\\#/) { print }
                    else { if (\$18 <= 2) { print } }
                }' ${TumorReplicateId}_mixMHC2pred_all.tsv > ${TumorReplicateId}_mixMHC2pred_filtered.tsv
            """
        else
            """
            true
            """
    }
}

// add CCF clonality to neoepitopes result files
process addCCF {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/neoantigens/$TumorReplicateId/",
        saveAs: {
            fileName ->
                targetFile = fileName
                if(fileName.indexOf("_MHCI_") >= 0) {
                    targetFile = "Class_I/" + file(fileName).getName()
                } else if(fileName.indexOf("_MHCII_") >= 0) {
                    targetFile = "Class_II/" + file(fileName).getName()
                }
                return "$targetFile"
        },
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        file(epitopes),
        file(CCF),
        val(ascatOK),
        val(sequenzaOK)
    ) from concat_mhcI_filtered_files_out_addCCF_ch0
        .concat(
                concat_mhcI_all_files_out_addCCF_ch0,
                concat_mhcII_filtered_files_out_addCCF_ch0,
                concat_mhcII_all_files_out_addCCF_ch0
        )
        .combine(Clonality_out_ch0, by: 0)

    output:
    file(outfile)
    file("INFO.txt") optional true

    script:
    outfile = (ascatOK || sequenzaOK) ? epitopes.baseName + "_ccf.tsv" : epitopes
    if (ascatOK || sequenzaOK)
        """
        add_CCF.py \\
            --neoepitopes ${epitopes} \\
            --ccf ${CCF} \\
            --outfile ${outfile}
        """
    else
        """
        echo "WARNING: neither ASCAT nor Sequenza produced results: clonality information missing" > INFO.txt
        """
}

/*
  Immunogenicity scoring
*/

process csin {

    label 'nextNEOpiENV'

    tag "$TumorReplicateId"

    publishDir "$params.outputDir/analyses/$TumorReplicateId/14_CSiN/",
        mode: params.publishDirMode

    input:
    set (
        TumorReplicateId,
        file("*_MHCI_all_epitopes.tsv"),
        file("*_MHCII_all_epitopes.tsv")
    ) from MHCI_all_epitopes
        .combine(MHCII_all_epitopes, by:0)

    output:
    set(
        TumorReplicateId,
        file("${TumorReplicateId}_CSiN.tsv")
    ) into sample_info_csin

    script:
    """
    CSiN.py --MHCI_tsv *_MHCI_all_epitopes.tsv \\
        --MHCII_tsv *_MHCII_all_epitopes.tsv \\
        --rank $params.csin_rank \\
        --ic50 $params.csin_ic50 \\
        --gene_exp $params.csin_gene_exp \\
        --output ./${TumorReplicateId}_CSiN.tsv
    """
}

igs_chck_file = file(workflow.workDir + "/.igs_install_ok.chck")
igs_target = workflow.workDir + "/IGS"
if(( ! igs_chck_file.exists() || igs_chck_file.isEmpty()) && params.IGS == "") {
    process install_IGS {

        tag 'install IGS'

        // do not cache
        cache false

        output:
        file(".igs_install_ok.chck") into igs_chck_ch

        script:
        """
        mkdir -p ${igs_target} && \\
        curl -sLk ${params.IGS_script_url} -o ${igs_target}/NeoAg_immunogenicity_predicition_GBM.R && \\
        curl -sLk ${params.IGS_model_url} -o ${igs_target}/Final_gbm_model.rds && \\
        patch -p0 ${igs_target}/NeoAg_immunogenicity_predicition_GBM.R ${baseDir}/assets/NeoAg_immunogenicity_predicition_GBM.patch && \\
        chmod +x ${igs_target}/NeoAg_immunogenicity_predicition_GBM.R  && \\
        echo "OK" > .igs_install_ok.chck && \\
        cp -f .igs_install_ok.chck ${igs_chck_file}
        """
    }
} else if (( ! igs_chck_file.exists() || igs_chck_file.isEmpty()) && params.IGS != "") {
    process link_IGS {

        tag 'link IGS'

        // do not cache
        cache false

        output:
        file(".igs_install_ok.chck") into igs_chck_ch

        script:
        """
        ln -s ${params.IGS} ${igs_target} && \\
        echo "OK" > .igs_install_ok.chck && \\
        cp -f .igs_install_ok.chck ${igs_chck_file}
        """
    }
} else {
    igs_chck_ch = Channel.fromPath(igs_chck_file)
}


process immunogenicity_scoring {

    label 'IGS'

    tag "$TumorReplicateId"

    // TODO: check why sometimes this fails: workaround ignore errors
    errorStrategy 'ignore'

    publishDir "$params.outputDir/analyses/$TumorReplicateId/14_IGS/",
        mode: params.publishDirMode

    input:
    set (
        TumorReplicateId,
        file(pvacseq_file)
    ) from MHCI_final_immunogenicity
    // val(TumorReplicateId) from mhCI_tag_immunogenicity
    // file pvacseq_file from MHCI_final_immunogenicity

    output:
    file("${TumorReplicateId}_Class_I_immunogenicity.tsv")

    script:
    """
    get_epitopes.py \\
        --pvacseq_out $pvacseq_file \\
        --sample_id $TumorReplicateId \\
        --output ./${TumorReplicateId}_epitopes.tsv
    NR_EPI=`wc -l ./${TumorReplicateId}_epitopes.tsv | cut -d" " -f 1`
    if [ \$NR_EPI -gt 1 ]; then
        ${igs_target}/NeoAg_immunogenicity_predicition_GBM.R \\
            ./${TumorReplicateId}_epitopes.tsv ./${TumorReplicateId}_temp_immunogenicity.tsv \\
            ${igs_target}/Final_gbm_model.rds
        immuno_score.py \\
            --pvacseq_tsv $pvacseq_file \\
            --score_tsv ${TumorReplicateId}_temp_immunogenicity.tsv \\
            --output ${TumorReplicateId}_Class_I_immunogenicity.tsv
    fi
    """
}

if(params.TCR) {

    mixcr_chck_file = file(baseDir + "/bin/.mixcr_install_ok.chck")
    mixcr_target = baseDir + "/bin/"
    if(!mixcr_chck_file.exists() && params.MIXCR == "") {
        process install_mixcr {

            tag 'install mixcr'

            // do not cache
            cache false

            output:
            file(".mixcr_install_ok.chck") into (
                mixcr_chck_ch0,
                mixcr_chck_ch1,
                mixcr_chck_ch2
            )

            script:
            """
            curl -sLk ${params.MIXCR_url} -o mixcr.zip && \\
            unzip mixcr.zip && \\
            chmod +x mixcr*/mixcr && \\
            cp -f mixcr*/mixcr ${mixcr_target} && \\
            cp -f mixcr*/mixcr.jar ${mixcr_target} && \\
            touch .mixcr_install_ok.chck && \\
            cp -f .mixcr_install_ok.chck ${mixcr_chck_file}
            """
        }
    } else if (!mixcr_chck_file.exists() && params.MIXCR != "") {
        process link_mixcr {

            tag 'link mixcr'

            // do not cache
            cache false

            output:
            file(".mixcr_install_ok.chck") into (
                mixcr_chck_ch0,
                mixcr_chck_ch1,
                mixcr_chck_ch2
            )

            script:
            """
            ln -s ${params.MIXCR}/mixcr ${mixcr_target} && \\
            ln -s ${params.MIXCR}/mixcr.jar ${mixcr_target} && \\
            touch .mixcr_install_ok.chck && \\
            cp -f .mixcr_install_ok.chck ${mixcr_chck_file}
            """
        }
    } else {
        mixcr_chck_ch = Channel.fromPath(mixcr_chck_file)
        (mixcr_chck_ch0, mixcr_chck_ch1, mixcr_chck_ch2) = mixcr_chck_ch.into(3)
    }


    process mixcr_DNA_tumor {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/15_BCR_TCR",
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(readFWD),
            file(readREV),
            file(mixcr_chck_file)
        ) from reads_tumor_mixcr_DNA_ch
            .combine(mixcr_chck_ch0)

        output:
        set(
            TumorReplicateId,
            file("${TumorReplicateId}_mixcr_DNA.clonotypes.ALL.txt"),
        )

        script:
        reads = (single_end) ? readFWD : readFWD + " " + readREV
        """
        mixcr analyze shotgun \\
            --threads ${task.cpus} \\
            --species hs \\
            --starting-material dna \\
            --only-productive \\
            $reads \\
            ${TumorReplicateId}_mixcr_DNA
        """
    }

    process mixcr_DNA_normal {

        label 'nextNEOpiENV'

        tag "$TumorReplicateId"

        publishDir "$params.outputDir/analyses/$TumorReplicateId/15_BCR_TCR",
            mode: params.publishDirMode

        input:
        set(
            TumorReplicateId,
            NormalReplicateId,
            file(readFWD),
            file(readREV),
            file(mixcr_chck_file)
        ) from reads_normal_mixcr_DNA_ch
            .combine(mixcr_chck_ch1)

        output:
        set(
            NormalReplicateId,
            file("${NormalReplicateId}_mixcr_DNA.clonotypes.ALL.txt"),
        )

        script:
        reads = (single_end) ? readFWD : readFWD + " " + readREV
        """
        mixcr analyze shotgun \\
            --threads ${task.cpus} \\
            --species hs \\
            --starting-material dna \\
            --only-productive \\
            $reads \\
            ${NormalReplicateId}_mixcr_DNA
        """
    }

    if (have_RNAseq) {
        process mixcr_RNA {

            label 'nextNEOpiENV'

            tag "$TumorReplicateId"

            publishDir "$params.outputDir/analyses/$TumorReplicateId/15_BCR_TCR",
                mode: params.publishDirMode

            input:
            set(
                TumorReplicateId,
                NormalReplicateId,
                file(readRNAFWD),
                file(readRNAREV),
                file(mixcr_chck_file)
            ) from reads_tumor_mixcr_RNA_ch
                .combine(mixcr_chck_ch2)

            output:
            set(
                TumorReplicateId,
                file("${TumorReplicateId}_mixcr_RNA.clonotypes.ALL.txt"),
            )

            script:
            readsRNA = (single_end_RNA) ? readRNAFWD : readRNAFWD + " " + readRNAREV
            """
            mixcr analyze shotgun \\
                --threads ${task.cpus} \\
                --species hs \\
                --starting-material rna \\
                --only-productive \\
                $readsRNA \\
                ${TumorReplicateId}_mixcr_RNA
            """
        }
    }
}

process collectSampleInfo {

    label 'nextNEOpiENV'

    publishDir "${params.outputDir}/neoantigens/$TumorReplicateId/",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        file(csin),
        file(tmb),
        file(tmb_coding)
    ) from sample_info_csin
        .combine(sample_info_tmb, by: 0)
        .combine(sample_info_tmb_coding, by: 0)

    output:
    file("${TumorReplicateId}_sample_info.tsv")

    script:
    """
    mkSampleInfo.py \\
        --sample_name ${TumorReplicateId} \\
        --csin ${csin} \\
        --tmb ${tmb} \\
        --tmb_coding ${tmb_coding} \\
        --out ${TumorReplicateId}_sample_info.tsv
    """
}

/*
***********************************
*  Generate final multiQC output  *
***********************************
*/
process multiQC {

    label 'nextNEOpiENV'

    publishDir "${params.outputDir}/analyses/$TumorReplicateId/QC",
        mode: params.publishDirMode

    input:
    set(
        TumorReplicateId,
        NormalReplicateId,
        file("*"),
        file("*"),
        file("*"),
        file("*"),
        file("*"),
        file("*"),
        file("*"),
        file("*")
    )   from ch_fastqc
            .combine(ch_fastp_tumor, by: [0,1])
            .combine(ch_fastp_normal, by: [0,1])
            .combine(ch_fastqc_trimmed, by: [0,1])
            .combine(ch_fastp_RNAseq, by: [0,1])
            .combine(ch_fastqc_trimmed_RNAseq, by: [0,1])
            .combine(alignmentMetricsTumor_ch, by: [0,1])
            .combine(alignmentMetricsNormal_ch, by: [0,1])

    output:
    file("multiqc_data/*")
    file("multiqc_report.html")

    script:
    """
    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8
    multiqc .
    """

}


/*
________________________________________________________________________________

                            F U N C T I O N S
________________________________________________________________________________

*/

def mkTmpDir(d) {
    myTmpDir = file(d)
    result = myTmpDir.mkdirs()
    if (result) {
        println("tmpDir: " + myTmpDir.toRealPath())
    } else {
        exit 1, "Cannot create directory: " + myTmpDir
    }
    return myTmpDir.toRealPath()
}

def checkParamReturnFileReferences(item) {
    params."${item}" = params.references."${item}"
    return file(params."${item}")
}

def checkParamReturnFileDatabases(item) {
    params."${item}" = params.databases."${item}"
    return file(params."${item}")
}

def setExomeCaptureKit(captureKit) {
    params.references.BaitsBed = params.exomeCaptureKits[ captureKit ].BaitsBed
    params.references.RegionsBed = params.exomeCaptureKits[ captureKit ].RegionsBed
}

def defineReference() {
    if(params.WES) {
        if (params.references.size() != 20) exit 1, """
        ERROR: Not all References needed found in configuration
        Please check if genome file, genome index file, genome dict file, bwa reference files, vep reference file and interval file is given.
        """
        return [
            'RefFasta'          : checkParamReturnFileReferences("RefFasta"),
            'RefIdx'            : checkParamReturnFileReferences("RefIdx"),
            'RefDict'           : checkParamReturnFileReferences("RefDict"),
            'RefChrLen'         : checkParamReturnFileReferences("RefChrLen"),
            'RefChrDir'         : checkParamReturnFileReferences("RefChrDir"),
            'BwaRef'            : checkParamReturnFileReferences("BwaRef"),
            'VepFasta'          : params.references.VepFasta,
            'BaitsBed'          : checkParamReturnFileReferences("BaitsBed"),
            'RegionsBed'        : checkParamReturnFileReferences("RegionsBed"),
            'YaraIndexDNA'      : checkParamReturnFileReferences("YaraIndexDNA"),
            'YaraIndexRNA'      : checkParamReturnFileReferences("YaraIndexRNA"),
            'HLAHDFreqData'     : checkParamReturnFileReferences("HLAHDFreqData"),
            'HLAHDGeneSplit'    : checkParamReturnFileReferences("HLAHDGeneSplit"),
            'HLAHDDict'         : checkParamReturnFileReferences("HLAHDDict"),
            'STARidx'           : checkParamReturnFileReferences("STARidx"),
            'AnnoFile'          : checkParamReturnFileReferences("AnnoFile"),
            'ExonsBED'          : checkParamReturnFileReferences("ExonsBED"),
            'acLoci'            : checkParamReturnFileReferences("acLoci"),
            'acLociGC'          : checkParamReturnFileReferences("acLociGC"),
            'SequenzaGC'        : checkParamReturnFileReferences("SequenzaGC")
        ]
    } else {
        if (params.references.size() < 18) exit 1, """
        ERROR: Not all References needed found in configuration
        Please check if genome file, genome index file, genome dict file, bwa reference files, vep reference file and interval file is given.
        """
        return [
            'RefFasta'          : checkParamReturnFileReferences("RefFasta"),
            'RefIdx'            : checkParamReturnFileReferences("RefIdx"),
            'RefDict'           : checkParamReturnFileReferences("RefDict"),
            'RefChrLen'         : checkParamReturnFileReferences("RefChrLen"),
            'RefChrDir'         : checkParamReturnFileReferences("RefChrDir"),
            'BwaRef'            : checkParamReturnFileReferences("BwaRef"),
            'VepFasta'          : params.references.VepFasta,
            'BaitsBed'          : "",
            'YaraIndexDNA'      : checkParamReturnFileReferences("YaraIndexDNA"),
            'YaraIndexRNA'      : checkParamReturnFileReferences("YaraIndexRNA"),
            'HLAHDFreqData'     : checkParamReturnFileReferences("HLAHDFreqData"),
            'HLAHDGeneSplit'    : checkParamReturnFileReferences("HLAHDGeneSplit"),
            'HLAHDDict'         : checkParamReturnFileReferences("HLAHDDict"),
            'STARidx'           : checkParamReturnFileReferences("STARidx"),
            'AnnoFile'          : checkParamReturnFileReferences("AnnoFile"),
            'ExonsBED'          : checkParamReturnFileReferences("ExonsBED"),
            'acLoci'            : checkParamReturnFileReferences("acLoci"),
            'acLociGC'          : checkParamReturnFileReferences("acLociGC"),
            'SequenzaGC'        : checkParamReturnFileReferences("SequenzaGC")
        ]
    }
}

def defineDatabases() {
    if (params.databases.size() < 15) exit 1, """
    ERROR: Not all Databases needed found in configuration
    Please check if Mills_and_1000G_gold_standard, CosmicCodingMuts, DBSNP, GnomAD, and knownIndels are given.
    """
    return [
        'MillsGold'      : checkParamReturnFileDatabases("MillsGold"),
        'MillsGoldIdx'   : checkParamReturnFileDatabases("MillsGoldIdx"),
        'hcSNPS1000G'    : checkParamReturnFileDatabases("hcSNPS1000G"),
        'hcSNPS1000GIdx' : checkParamReturnFileDatabases("hcSNPS1000GIdx"),
        'HapMap'         : checkParamReturnFileDatabases("HapMap"),
        'HapMapIdx'      : checkParamReturnFileDatabases("HapMapIdx"),
        'DBSNP'          : checkParamReturnFileDatabases("DBSNP"),
        'DBSNPIdx'       : checkParamReturnFileDatabases("DBSNPIdx"),
        'GnomAD'         : checkParamReturnFileDatabases("GnomAD"),
        'GnomADIdx'      : checkParamReturnFileDatabases("GnomADIdx"),
        'GnomADfull'     : checkParamReturnFileDatabases("GnomADfull"),
        'GnomADfullIdx'  : checkParamReturnFileDatabases("GnomADfullIdx"),
        'KnownIndels'    : checkParamReturnFileDatabases("KnownIndels"),
        'KnownIndelsIdx' : checkParamReturnFileDatabases("KnownIndelsIdx"),
        'vep_cache'      : params.databases.vep_cache
    ]
}

def checkToolAvailable(tool, check, errMode) {
    def checkResult = false
    def res = ""

    if (check == "inPath") {
        def chckCmd = "which " + tool
        res = chckCmd.execute().text.trim()
    }
    if (check == "exists") {
        if (file(tool).exists()) {
            res = tool
        }
    }

    if (res == "") {
        def msg = tool + " not found, please make sure " + tool + " is installed"

        if(errMode == "err") {
            msg = "ERROR: " + msg
            msg = (check == "inPath") ? msg + " and in your \$PATH" : msg
            exit(1, msg)
        } else {
            msg = "Warning: " + msg
            msg = (check == "inPath") ? msg + " and in your \$PATH" : msg
            println("Warning: " + msg)
        }
    } else {
        println("Found " + tool + " at: " + res)
        checkResult = true
    }

    return checkResult
}

def showLicense() {

    licenseFile = file(baseDir + "/LICENSE")
    log.info licenseFile.text

    log.info ""
    log.warn "To accept the licence terms, please rerun with '--accept_license'"
    log.info ""

    exit 1
}

def acceptLicense() {
    log.info ""
    log.warn "I have read and accept the licence terms"
    log.info ""

    licenseChckFile = file(baseDir + "/.license_accepted.chck")
    licenseChckFile.text = "License accepted by " + workflow.userName + " on "  + workflow.start

    return true
}

def checkLicense() {
    licenseChckFile = file(baseDir + "/.license_accepted.chck")

    if(!licenseChckFile.exists()) {
        showLicense()
    } else {
        return true
    }
}

def check_seqLibTypes_ok(seqLib_ch, analyte) {
    seqLibs = seqLib_ch.toList().get()
    pe_count = 0
    se_count = 0
    seqLibField = (analyte == "DNA") ? 4 : 3
    for (seqLib in seqLibs) {
        pe_count += (seqLib[seqLibField] == "PE") ? 1 : 0
        se_count += (seqLib[seqLibField] == "SE") ? 1 : 0
        if (seqLib[seqLibField] == "MIXED") {
            exit 1, "Please do not mix pe and se for tumor/normal pairs: " + seqLib[0] + " - Not supported"
        }
    }

    if (pe_count != 0 && se_count != 0) {
        for (seqLib in seqLibs) {
            println(seqLib[0] + " : " + seqLib[seqLibField] + " : " + analyte)
        }
        exit 1, "Please do not mix pe and se " + analyte + "read samples in batch file. Create a separate batch file for se and pe " + analyte + "samples"
    }
    return true
}


def helpMessage() {
    log.info ""
    log.info "----------------------------"
    log.info "--        U S A G E       "
    log.info "----------------------------"
    log.info ""
    log.info ' nextflow run nextNEOpi.nf -config conf/params.config ["--readsTumor" "--readsNormal" | "--bamTumor" "--bamNormal"] | ["--batchFile"] ["--bam"] "-profile [conda|singularity],[cluster]" ["-resume"]'
    log.info ""
    log.info "-------------------------------------------------------------------------"
    log.info ""
    log.info ""
    log.info " Mandatory arguments:"
    log.info " --------------------"
    log.info "--batchFile  (RECOMMENDED)"
    log.info "   or"
    log.info "--readsTumor \t\t reads_{1,2}.fastq \t\t paired-end reads; FASTQ files (can be zipped)"
    log.info "--readsNormal \t\t reads_{1,2}.fastq \t\t paired-end reads; FASTQ files (can be zipped)"
    log.info "   or"
    log.info "--bamTumor \t\t tumor_1.bam \t\t ; tumor BAM file"
    log.info "--bamNormal \t\t normal_1.bam \t\t ; normal BAM file"
    log.info ""
    log.info "CSV-file, paired-end T/N reads, paired-end RNAseq reads:"

    log.info "tumorSampleName,readsTumorFWD,readsTumorREV,normalSampleName,readsNormalFWD,readsNormalREV,readsRNAseqFWD,readsRNAseqREV,HLAfile,sex"
    log.info "sample1,Tumor1_reads_1.fastq,Tumor1_reads_2.fastq,normal1,Normal1_reads_1.fastq,Normal1_reads_2.fastq,Tumor1_RNAseq_reads_1.fastq,Tumor1_RNAseq_reads_2.fastq,None,XX"
    log.info "sample2,Tumor2_reads_1.fastq,Tumor2_reads_2.fastq,normal2,Normal2_reads_1.fastq,Normal2_reads_2.fastq,Tumor2_RNAseq_reads_1.fastq,Tumor2_RNAseq_reads_2.fastq,None,XY"
    log.info "..."
    log.info "sampleN,TumorN_reads_1.fastq,TumorN_reads_2.fastq,normalN,NormalN_reads_1.fastq,NormalN_reads_2.fastq,TumorN_RNAseq_reads_1.fastq,TumorN_RNAseq_reads_2.fastq,None,XX"

    log.info "CSV-file, single-end T/N reads, single-end RNAseq reads:"

    log.info "tumorSampleName,readsTumorFWD,readsTumorREV,normalSampleName,readsNormalFWD,readsNormalREV,readsRNAseqFWD,readsRNAseqREV,HLAfile,sex"
    log.info "sample1,Tumor1_reads_1.fastq,None,normal1,Normal1_reads_1.fastq,None,Tumor1_RNAseq_reads_1.fastq,None,None,XX"
    log.info "sample2,Tumor2_reads_1.fastq,None,normal2,Normal2_reads_1.fastq,None,Tumor1_RNAseq_reads_1.fastq,None,None,XY"
    log.info "..."
    log.info "sampleN,TumorN_reads_1.fastq,None,normalN,NormalN_reads_1.fastq,None,Tumor1_RNAseq_reads_1.fastq,None,None,None"

    log.info "CSV-file, single-end T/N reads, NO RNAseq reads:"

    log.info "tumorSampleName,readsTumorFWD,readsTumorREV,normalSampleName,readsNormalFWD,readsNormalREV,readsRNAseqFWD,readsRNAseqREV,HLAfile,sex"
    log.info "sample1,Tumor1_reads_1.fastq,None,normal1,Normal1_reads_1.fastq,None,None,None,None,XX"
    log.info "sample2,Tumor2_reads_1.fastq,None,normal2,Normal2_reads_1.fastq,None,None,None,None,XY"
    log.info "..."
    log.info "sampleN,TumorN_reads_1.fastq,None,normalN,NormalN_reads_1.fastq,None,None,None,None,XX"


    log.info "Note: You must not mix samples with single-end and paired-end reads in a batch file. Though, it is possible to have for e.g. all"
    log.info "DNA reads paired-end and all RNAseq reads single-end or vice-versa."

    log.info "Note: in the HLAfile coulumn a user suppiled HLA types file may be specified for a given sample, see also --customHLA option below"

    log.info "Note: sex can be XX, female or Female, XY, male or Male. If not specified or \"None\" Male is assumed"
    log.info ""
    log.info "FASTQ files (can be zipped), if single-end reads are used put NO_FILE instead of *_reads_2.fastq in the REV fields"
    log.info ""
    log.info ""
    log.info ""
    log.info " All references, databases, software should be edited in the resources.config file"
    log.info ""
    log.info " For further options see the README.md, the params.config and process.config files"
    log.info "----------------------------------------------------------------------------------"
}

// workflow complete
workflow.onComplete {
    // Set up the e-mail variables
    def subject = "[icbi/nextNEOpi] Successful: $workflow.runName"
    if(!workflow.success){
        subject = "[icbi/nextNEOpi] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if(workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if(workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if(workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir" ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (params.email) {
        try {
            if( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
            // Try to send HTML e-mail using sendmail
            [ 'sendmail', '-t' ].execute() << sendmail_html
            log.info "[icbi/nextNEOpi] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
            // Catch failures and try with plaintext
            [ 'mail', '-s', subject, params.email ].execute() << email_txt
            log.info "[icbi/nextNEOpi] Sent summary e-mail to $params.email (mail)"
        }
    }

  // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outputDir}/Documentation/" )
    if( !output_d.exists() ) {
        output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }

    log.info "[icbi/nextNEOpi] Pipeline Complete! You can find your results in ${params.outputDir}"
}

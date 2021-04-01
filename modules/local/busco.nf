// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
options    = initOptions(params.options)

process BUSCO {
    tag "${bin}"

    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:'') }

    conda (params.enable_conda ? "bioconda::busco=5.1.0" : null)
    if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
        container "https://depot.galaxyproject.org/singularity/busco:5.1.0--py_1"
    } else {
        container "quay.io/biocontainers/busco:5.1.0--py_1"
    }

    input:
    tuple val(meta), path(bin)
    path(db)
    path(download_folder)

    output:
    tuple val(meta), path("short_summary.specific.*.${bin}.txt"), emit: summary
    path("${bin}_busco.log")
    path("${bin}_buscos.faa.gz") optional true
    path("${bin}_buscos.fna.gz") optional true
    path '*.version.txt'                                        , emit: version

    script:
    def software = getSoftwareName(task.process)
    if( workflow.profile.toString().indexOf("conda") == -1)
        cp_augustus_config = "Y"
    else
        cp_augustus_config = "N"

    if (params.busco_reference)
        p = "--lineage_dataset dataset/${db}"
    else if (params.busco_download_path)
        p = "--auto-lineage --offline --download_path ${params.busco_download_path}"
    else
        p = "--auto-lineage"
    """
    # ensure augustus has write access to config directory
    if [ ${cp_augustus_config} = "Y" ] ; then
        cp -r /usr/local/config/ augustus_config/
        export AUGUSTUS_CONFIG_PATH=augustus_config
    fi

    # place db in extra folder to ensure BUSCO recognizes it as path (instead of downloading it)
    if [ ${params.busco_reference} != "false" ] ; then
        mkdir dataset
        mv ${db} dataset/
    fi

    busco ${p} \
        --mode genome \
        --in ${bin} \
        --cpu "${task.cpus}" \
        --out "BUSCO" > ${bin}_busco.log

    # get used db name
    # (set nullgob: if pattern matches no files, expand to a null string rather than to itself)
    shopt -s nullglob
    summaries=(BUSCO/short_summary.specific.*.BUSCO.txt)
    if [ \${#summaries[@]} -ne 1 ]; then
        echo "ERROR: none or multiple 'BUSCO/short_summary.specific.*.BUSCO.txt' files found. Expected one."
        exit 1
    fi
    [[ \$summaries =~ BUSCO/short_summary.specific.(.*).BUSCO.txt ]];
    db_name="\${BASH_REMATCH[1]}"
    echo "Used database: \${db_name}"

    cp BUSCO/short_summary.specific.\${db_name}.BUSCO.txt short_summary.specific.\${db_name}.${bin}.txt

    for f in BUSCO/run_\${db_name}/busco_sequences/single_copy_busco_sequences/*faa; do
        cat BUSCO/run_\${db_name}/busco_sequences/single_copy_busco_sequences/*faa | gzip >${bin}_buscos.faa.gz
        break
    done
    for f in BUSCO/run_\${db_name}/busco_sequences/single_copy_busco_sequences/*fna; do
        cat BUSCO/run_\${db_name}/busco_sequences/single_copy_busco_sequences/*fna | gzip >${bin}_buscos.fna.gz
        break
    done

    busco --version | sed "s/BUSCO //" > ${software}.version.txt
    """
}

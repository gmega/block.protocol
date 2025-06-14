#!/usr/bin/env bash
#
# Repeatedly runs a two-node experiment and times the download.
#
set -e -o pipefail

# Source utility functions
source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/codex.sh"
setup_process_tracking


N_REPS=10
BLOCK_SIZE="1M"
BLOCK_COUNTS=(50 100 200 300 400 600 800)
#BLOCK_COUNTS=(400)
OUTPUT_LOG="${1}"
LAUNCH_MODE="${2:-regular}"  # Get launch mode from second argument, default to "regular"
#export CODEX_LOG_LEVEL='INFO;trace:blockexcnetwork,blockexcengine,discoveryengine'
export CODEX_LOG_LEVEL='INFO'

echoerr "Output log is ${OUTPUT_LOG}"
echoerr "Launch mode is ${LAUNCH_MODE}"

# Launch the Codex network with 2 nodes and specified launch mode
launch_codex_network 2 "$LAUNCH_MODE"

echo "block_count,run,wallclock,user,system" > ${OUTPUT_LOG}

for block_count in ${BLOCK_COUNTS[@]}; do
    for i in $(seq 1 ${N_REPS}); do
        echoerr "Running experiment ${i}/${N_REPS} - blockcount: ${block_count}"

        # Create random file
        create_file ${BLOCK_SIZE} ${block_count}

        # Upload to node 1
        upload 1

        TIMEFORMAT="${block_count},${i},%E,%U,%S"
        # Time the download from node 2
        { time download 2 ${CID} &> /dev/null ; } 2>> ${OUTPUT_LOG}

        if [ "${last_download_sha1}" != "${last_upload_sha1}" ]; then
            echoerr "Download failed: SHA1 mismatch (${last_download_sha1} != ${last_upload_sha1})"
            exit 1
        fi
    done
done

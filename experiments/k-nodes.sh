#!/usr/bin/env bash
#
# Runs a k-node experiment: uploads to Node 1, then fires
# simultaneous downloads from the remaining k-1 nodes and times them.
#
set -e -o pipefail

# shellcheck source=./codex.sh
source "$(dirname "$0")/codex.sh"

setup_process_tracking

# Default values
N_REPS=${N_REPS:-10}
FILE_SIZE_MB=(10)
NUM_NODES=${NUM_NODES:-3}  # Default to 3 nodes if not specified

# Parse command-line arguments
OUTPUT_LOG="${1:-k-nodes-experiment.csv}"  # Default log name if not specified
NUM_NODES="${2:-$NUM_NODES}"               # Get number of nodes from second argument or use default
export CODEX_LOG_LEVEL='INFO'
#export CODEX_LOG_LEVEL='INFO;trace:blockexcnetwork,blockexcengine,discoveryengine'

echoerr "Number of nodes: ${NUM_NODES}"
echoerr "Output log is ${OUTPUT_LOG}"

# Validate input
if [ "$NUM_NODES" -lt 2 ]; then
    echoerr "Error: Number of nodes must be at least 2"
    exit 1
fi

# Wipes out everything.
rm -rf "${CODEX_TEMP}" "${CODEX_DATA}" "${CODEX_LOGS}"
mkdir -p "${CODEX_TEMP}" "${CODEX_DATA}" "${CODEX_LOGS}"

# Launch the Codex network with k nodes and specified launch mode
launch_codex_network "$NUM_NODES" "$LAUNCH_MODE"

# Prepare the output log header
echo "block_count,run,node,wallclock,user,system" > "${OUTPUT_LOG}"

for block_count in "${FILE_SIZE_MB[@]}"; do
    for i in $(seq 1 "${N_REPS}"); do
        echoerr "Running experiment ${i}/${N_REPS} - blockcount: ${block_count} with ${NUM_NODES} nodes"

        # Create random file
        create_file "1M" "${block_count}"

        # Uploads to node 1
        upload 1

        # Start concurrent downloads from all nodes except node 1
        for node in $(seq 2 "${NUM_NODES}"); do
            # String for formatting download timings for this node.
            export TIMEFORMAT="${block_count},${i},${node},%E,%U,%S"

            download_async "${node}" "${last_upload_cid}"
        done

        await_for_downloads

        for node in $(seq 2 "${NUM_NODES}"); do
            check_download "${node}"
            cat "${CODEX_TEMP}/download-timing-${node}.log" >> "${OUTPUT_LOG}"
        done
    done

    # Wipes out experiment data.
    rm -rf "${CODEX_TEMP}"
done

echoerr "Experiment completed. Results saved to ${OUTPUT_LOG}"

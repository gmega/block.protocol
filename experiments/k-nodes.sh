#!/usr/bin/env bash
#
# Runs a k-node experiment: uploads to Node 1, then fires
# simultaneous downloads from the remaining k-1 nodes and times them.
#
set -e -o pipefail

# Source utility functions
source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/codex.sh"
setup_process_tracking

# Default values
N_REPS=10
BLOCK_SIZE="1M"
BLOCK_COUNTS=(1000)
NUM_NODES=${NUM_NODES:-2}  # Default to 3 nodes if not specified

# Parse command-line arguments
OUTPUT_LOG="${1:-k-nodes-experiment.csv}"  # Default log name if not specified
NUM_NODES="${2:-$NUM_NODES}"               # Get number of nodes from second argument or use default
LAUNCH_MODE="${3:-regular}"                # Get launch mode from third argument, default to "regular"
# export CODEX_LOG_LEVEL='INFO'
export CODEX_LOG_LEVEL='INFO;trace:blockexcnetwork,blockexcengine,discoveryengine'

echoerr "Number of nodes: ${NUM_NODES}"
echoerr "Output log is ${OUTPUT_LOG}"
echoerr "Launch mode is ${LAUNCH_MODE}"

# Validate input
if [ "$NUM_NODES" -lt 2 ]; then
    echoerr "Error: Number of nodes must be at least 2"
    exit 1
fi

# Launch the Codex network with k nodes and specified launch mode
launch_codex_network $NUM_NODES "$LAUNCH_MODE"

# Prepare the output log header
echo "block_count,run,node,wallclock,user,system" > ${OUTPUT_LOG}

for block_count in ${BLOCK_COUNTS[@]}; do
    for i in $(seq 1 ${N_REPS}); do
        echoerr "Running experiment ${i}/${N_REPS} - blockcount: ${block_count} with ${NUM_NODES} nodes"

        # Create random file
        create_file ${BLOCK_SIZE} ${block_count}

        # Create temporary directory to store timing results
        tmp_dir=$(mktemp -d)

        # Directly compute SHA1 of the test file before uploading
        UPLOAD_SHA1=$(sha1sum /tmp/testfile | cut -d' ' -f1)
        echo "$UPLOAD_SHA1" > "${tmp_dir}/upload_sha1.txt"
        echoerr "Calculated upload SHA1: $UPLOAD_SHA1"

        # Upload to node 1
        CID=$(upload 1)

        # Array to store background process PIDs
        pids=()

        # Start downloads from all nodes except node 1 (the uploader) in parallel
        for node in $(seq 2 $NUM_NODES); do
            (
                # Each node gets its own subshell
                node_tmp_file="${tmp_dir}/node-${node}.log"
                node_output_file="${tmp_dir}/download-${node}.bin"
                echoerr "Starting download from node ${node}"

                # Use a specific format for the timing output
                TIMEFORMAT="${block_count},${i},${node},%E,%U,%S"

                # Calculate API port for this node
                api_port=$((8080 + node - 1))

                # Time the download and save results to the temp file
                { time curl -s -X GET "http://localhost:${api_port}/api/codex/v1/data/${CID}/network/stream" \
                  -o "$node_output_file" ; } 2> "$node_tmp_file"

                # Calculate SHA1 for verification
                node_download_sha1=$(sha1sum "$node_output_file" | cut -d' ' -f1)

                # Store SHA1 for verification
                echo "$node_download_sha1" > "${tmp_dir}/sha1-${node}.txt"

                echoerr "Download from node ${node} completed with SHA1: $node_download_sha1"
            ) &
            # Store the PID of this specific background process
            pids+=($!)
        done

        # Wait for the specific download processes to complete
        for pid in "${pids[@]}"; do
            echoerr "Waiting for process $pid to complete"
            wait $pid || echoerr "Process $pid failed with exit code $?"
        done
        echoerr "All downloads completed"

        # Collect and append all timing results to the main log
        # First read the upload SHA1 from file
        upload_sha1=$(cat "${tmp_dir}/upload_sha1.txt")
        echoerr "Read upload SHA1 from file: $upload_sha1"

        for node in $(seq 2 $NUM_NODES); do
            cat "${tmp_dir}/node-${node}.log" >> "${OUTPUT_LOG}"

            # Verify SHA1
            node_sha1=$(cat "${tmp_dir}/sha1-${node}.txt")
            echoerr "Comparing node ${node} SHA1: $node_sha1 with upload SHA1: $upload_sha1"

            if [ "$node_sha1" != "$upload_sha1" ]; then
                echoerr "Download failed for node ${node}: SHA1 mismatch (${node_sha1} != ${upload_sha1})"
                exit 1
            else
                echoerr "Download verified for node ${node}: SHA1 match"
            fi
        done

        # Clean up temp directory
        rm -rf "$tmp_dir"
    done
done

echoerr "Experiment completed. Results saved to ${OUTPUT_LOG}"

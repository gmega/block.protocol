#
# Utility functions for managing Codex nodes
#

# Function to launch a Codex node with the specified parameters
# Usage: launch_codex_node <node_number> <api_port> <disc_port> <bootstrap_param> <launch_mode>
launch_codex_node() {
    local node_num=$1
    local api_port=$2
    local disc_port=$3
    local bootstrap_param=$4
    local launch_mode=$5
    local log_file="./codex-logs/codex-${node_num}.log"
    local data_dir="./codex-data/codex-${node_num}"

    local cmd="$CODEX_BIN --nat:none --log-file=${log_file} --data-dir=${data_dir} --api-port=${api_port}"

    # Add discovery port if provided
    if [[ -n "$disc_port" ]]; then
        cmd="${cmd} --disc-port=${disc_port}"
    fi

    # Add bootstrap parameter if provided
    if [[ -n "$bootstrap_param" ]]; then
        cmd="${cmd} --bootstrap-node=${bootstrap_param}"
    fi

    echoerr "Start Codex node ${node_num}"

    if [[ "$launch_mode" == "gnometerm" ]]; then
        # Launch in gnome-terminal
        gnome-terminal --title="Codex Node ${node_num}" -- bash -c "${cmd}; exec bash" &
        track_last_process
    else
        # Launch in background
        ${cmd} &> /dev/null &
        track_last_process
    fi
}

# Function to get SPR from a Codex node with retries
# Usage: get_spr <api_port> <max_wait_seconds>
get_spr() {
    local api_port=$1
    local max_wait_seconds=${2:-20}
    local start_time=$(date +%s)
    local end_time=$((start_time + max_wait_seconds))
    local spr=""

    echoerr "Attempting to get SPR from node on port ${api_port}..."

    while [[ $(date +%s) -lt $end_time ]]; do
        spr=$(curl -s -m 2 -XGET localhost:${api_port}/api/codex/v1/debug/info | jq --raw-output .spr 2>/dev/null)

        # Check if we got a valid SPR (not empty and not null)
        if [[ -n "$spr" && "$spr" != "null" ]]; then
            echoerr "Successfully retrieved SPR after $(($(date +%s) - start_time)) seconds"
            echo "$spr"
            return 0
        fi

        # Wait before retrying
        sleep 1
    done

    echoerr "Failed to get SPR after ${max_wait_seconds} seconds"
    return 1
}

# Function to launch the Codex network with a specified number of nodes
# Usage: launch_codex_network <number_of_nodes> [launch_mode]
# launch_mode can be:
#   - "regular": Launch processes in background (default)
#   - "gnometerm": Launch each process in its own gnome-terminal
launch_codex_network() {
    local num_nodes=${1:-2}  # Default to 2 nodes if not specified
    local launch_mode=${2:-"regular"}  # Default to regular mode if not specified

    # Clean up any existing Codex data
    rm -rf ./codex-data ./codex-logs
    mkdir -p ./codex-data ./codex-logs

    # Start node 1 (first node doesn't need bootstrap)
    launch_codex_node 1 8080 "" "" "$launch_mode"

    # Get the SPR from the first node with retries (try for up to 20 seconds)
    export SPR=$(get_spr 8080 20)

    # Check if we got a valid SPR
    if [[ -z "$SPR" ]]; then
        echoerr "ERROR: Could not get SPR from first node. Exiting."
        exit 1
    fi

    echoerr "Bootstrap SPR is ${SPR}."

    # Start additional nodes (nodes 2 to num_nodes)
    for i in $(seq 2 $num_nodes); do
        local api_port=$((8080 + i - 1))
        local disc_port=$((8090 + i - 1))

        launch_codex_node "$i" "$api_port" "$disc_port" "$SPR" "$launch_mode"
    done
}

# Create a random file with specified block size and count
# Usage: create_file <block_size> <block_count> [output_file]
create_file() {
    local block_size=$1
    local block_count=$2
    local output_file=${3:-"/tmp/testfile"}
    
    echoerr "Creating file with block size: ${block_size}, block count: ${block_count}"
    dd if=/dev/urandom of=${output_file} bs=${block_size} count=${block_count} &> /dev/null
    echo ${output_file}
}

# Upload a file to a specified node
# Usage: upload <node_index> <file_path>
# Returns: Content ID (CID) of the uploaded file
upload() {
    local node_index=$1
    local file_path=${2:-"/tmp/testfile"}
    local api_port=$((8080 + node_index - 1))
    
    echoerr "Uploading file to node ${node_index} (port: ${api_port})"
    last_upload_cid=$(curl -s -X POST -T "${file_path}" http://localhost:${api_port}/api/codex/v1/data)
    last_upload_sha1=$(sha1sum ${file_path} | cut -d' ' -f1)
    echoerr "Upload sha1 is ${last_upload_sha1}"
    echo ${last_upload_cid}
}

# Download a file from a specified node
# Usage: download <node_index> <cid>
download() {
    local node_index=$1
    local cid=${2:-${last_upload_cid}}
    local api_port=$((8080 + node_index - 1))
    
    echoerr "Downloading file from node ${node_index} (port: ${api_port})"
    curl -s -X GET "http://localhost:${api_port}/api/codex/v1/data/${cid}/network/stream" -o /tmp/testfile-download
    last_download_sha1=$(sha1sum /tmp/testfile-download | cut -d' ' -f1)
    echoerr "Download sha1 is ${last_download_sha1}"
}

check_download() {
    if [ "${last_download_sha1}" != "${last_upload_sha1}" ]; then
        echoerr "Download failed: SHA1 mismatch (${last_download_sha1} != ${last_upload_sha1})"
        exit 1
    fi
}
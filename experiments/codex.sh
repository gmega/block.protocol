#!/usr/bin/env bash
#
# Utility functions for managing Codex nodes
#
set -e

# Node logs will be placed here.
export CODEX_LOGS=${CODEX_LOGS:-"./codex-logs"}
# Nodes data dirs will be placed here.
export CODEX_DATA=${CODEX_DATA:-"./codex-data"}
# Experiment temp data will be placed here.
export CODEX_TEMP=${CODEX_TEMP:-"./codex-temp"}

export ENABLE_MONITORING=${ENABLE_MONITORING:-true}

export UTILS_TEMP=${CODEX_TEMP}
DOWNLOAD_PIDS=()

# shellcheck source=./utils.sh
source "$(dirname "$0")/utils.sh"
# shellcheck source=./monitoring.sh
source "$(dirname "$0")/monitoring.sh"

if [[ "${CODEX_BIN}" == "" ]]; then
    echoerr "Error: CODEX_BIN is not set. Please set it to the path of the Codex binary."
    exit 1
fi

# Function to launch a Codex node with the specified parameters
# Usage: launch_codex_node <node_number> <api_port> <disc_port> <metrics_port> <bootstrap_param>
launch_codex_node() {
    local node_num=$1
    local api_port=$2
    local disc_port=$3
    metrics_port=$4
    local bootstrap_param=$5
    local log_file="./${CODEX_LOGS}/codex-${node_num}.log"
    local data_dir="./${CODEX_DATA}/codex-${node_num}"

    local cmd="$CODEX_BIN --nat:none --log-file=${log_file} --data-dir=${data_dir} --api-port=${api_port}"

    # Add discovery port if provided
    if [[ -n "$disc_port" ]]; then
        cmd="${cmd} --disc-port=${disc_port}"
    fi

    # Add metrics port if provided
    if [[ -n "$metrics_port" ]]; then
        cmd="${cmd} --metrics --metrics-port=${metrics_port}"
    fi

    # Add bootstrap parameter if provided
    if [[ -n "$bootstrap_param" ]]; then
        cmd="${cmd} --bootstrap-node=${bootstrap_param}"
    fi

    echoerr "Start Codex node ${node_num}"

    export metrics_port

    # Launch in background
    (
        if [[ -n "$metrics_port" ]]; then
            start_monitoring_node "${metrics_port}"
        fi
        ${cmd} &> /dev/null
        exit_code="$?"
        if [[ -n "$metrics_port" ]]; then
            stop_monitoring_node "${metrics_port}"
        fi
        store_exit_code "${exit_code}"
    ) &
    track_last_process
}

# Function to get SPR from a Codex node with retries
#
# Usage: get_spr <api_port> <max_wait_seconds>
get_spr() {
    local api_port=$1
    local max_wait_seconds=${2:-20}
    local spr=""

    local start_time
    start_time=$(date +%s)

    local end_time
    end_time=$((start_time + max_wait_seconds))

    echoerr "Attempting to get SPR from node on port ${api_port}..."

    while [[ $(date +%s) -lt $end_time ]]; do
        spr=$(curl -s -m 2 -XGET "localhost:${api_port}/api/codex/v1/debug/info" | jq --raw-output .spr 2>/dev/null)

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

# Launches a Codex network with a specified number of nodes
#
# Usage: launch_codex_network <number_of_nodes> [launch_mode]
# launch_mode can be:
#   - "regular": Launch processes in background (default)
#   - "gnometerm": Launch each process in its own gnome-terminal
launch_codex_network() {
    local num_nodes=${1}

    # Clean up any existing Codex data
    rm -rf "${CODEX_DATA}" "${CODEX_LOGS}"
    mkdir -p "${CODEX_DATA}" "${CODEX_LOGS}"

    # Start node 1 (first node doesn't need bootstrap)
    launch_codex_node 1 8080

    # Get the SPR from the first node with retries (try for up to 20 seconds)
    SPR=$(get_spr 8080 20)
    export SPR

    # Check if we got a valid SPR
    if [[ -z "$SPR" ]]; then
        echoerr "ERROR: Could not get SPR from first node. Exiting."
        exit 1
    fi

    echoerr "Bootstrap SPR is ${SPR}."

    # Start additional nodes (nodes 2 to num_nodes)
    for i in $(seq 2 "$num_nodes"); do
        local api_port=$((8080 + i - 1))
        local disc_port=$((8190 + i - 1))
        local metrics_port=$((8290 + i - 1))

        launch_codex_node "$i" "$api_port" "$disc_port" "$metrics_port" "$SPR"
        await_for_node "$api_port" 10
    done
}

await_for_node() {
    local api_port=$1
    local timeout=$2
    local start_time
    start_time=$(date +%s)
    local end_time
    end_time=$((start_time + "$timeout"))
    while [[ $(date +%s) -lt $end_time ]]; do
        if curl -s -XGET "localhost:${api_port}/api/codex/v1/debug/info" > /dev/null; then
            return 0
        fi
        sleep 1
    done
    echoerr "ERROR: Could not get SPR from node on port ${api_port}. Exiting."
    exit 1
}

# Creates a random file with specified block size and count in the experiment temp file.
#
# Usage: create_file <block_size> <block_count> [output_file]
create_file() {
    local block_size=$1
    local block_count=$2
    local output_file=${3:-"${CODEX_TEMP}/testfile"}

    echoerr "Creating file with block size: ${block_size}, block count: ${block_count}"
    dd if=/dev/urandom of="${output_file}" bs="${block_size}" count="${block_count}" &> /dev/null
    echo "${output_file}"
}

# Uploads a file to a specified node. Records the upload CID and SHA1 in last_upload_cid and last_upload_sha1.
#
# Usage: upload <node_index> <file_path>
# Returns: Content ID (CID) of the uploaded file
upload() {
    local node_index=$1
    local file_path=${2:-"${CODEX_TEMP}/testfile"}
    local api_port=$((8080 + node_index - 1))

    echoerr "Uploading file to node ${node_index} (port: ${api_port})"
    last_upload_cid=$(curl -s -X POST -T "${file_path}" "http://localhost:${api_port}/api/codex/v1/data")
    last_upload_sha1=$(sha1sum "${file_path}" | cut -d' ' -f1)
    echoerr "Upload sha1 is ${last_upload_sha1}"
    echo "${last_upload_cid}"
}

# Downloads a file from a specified node and awaits for completion.
download() {
    download_async "$@"
    await_for_downloads
}

# Downloads the file registered in last_upload_cid from a specified node as a background process into 
# "${CODEX_TEMP}/download-${node}". Logs timing information into "${CODEX_TEMP}/download-timing-${node}".
# Async downloads can be awaited by calling `await_for_downloads`.
#
# Usage: download <node_index> <cid>
download_async() {
    local node_index=$1
    local cid=${2:-${last_upload_cid}}
    local api_port=$((8080 + node_index - 1))

    echoerr "Downloading file from node ${node_index} (port: ${api_port})"
    (
        { time curl -X GET \
            "http://localhost:${api_port}/api/codex/v1/data/${cid}/network/stream"\
             -o "${CODEX_TEMP}/download-${node_index}" &> "${CODEX_TEMP}/download-status-${node_index}.log" ; store_last_exit_code ; }\
             2> "${CODEX_TEMP}/download-timing-${node_index}.log"
    ) &
    track_download
}

track_download() {
    DOWNLOAD_PIDS+=($!)
}

# Awaits for all pending async downloads to complete.
await_for_downloads() {
    echoerr "Awaiting for downloads"
    for pid in "${DOWNLOAD_PIDS[@]}"; do
        echoerr "Waiting for download process: [$pid]"
        if ! wait "$pid"; then
            echoerr "Download process $pid failed"
            exit 1
        fi
    done
    DOWNLOAD_PIDS=()
    echoerr "All downloads completed"
}

# Checks the last download issued to node $1 for SHA1 mismatch with the last upload.
# If the SHA1 of the downloaded file does not match the last upload's SHA1, it prints an error and exits.
#
# Usage: check_download <node_index>
check_download() {
    local node_index=$1
    local download_sha
    download_sha=$(sha1sum "${CODEX_TEMP}/download-${node_index}" | cut -d' ' -f1)

    if [ "${download_sha}" != "${last_upload_sha1}" ]; then
        echoerr "Download failed for node ${node_index}: SHA1 mismatch (${download_sha} != ${last_upload_sha1})"
        exit 1
    fi
}

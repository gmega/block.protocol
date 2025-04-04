#!/usr/bin/env bash
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
    local log_file="./codex-${node_num}.log"
    local data_dir="./codex-${node_num}"
    
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

# Function to launch the Codex network with a specified number of nodes
# Usage: launch_codex_network <number_of_nodes> [launch_mode]
# launch_mode can be:
#   - "regular": Launch processes in background (default)
#   - "gnometerm": Launch each process in its own gnome-terminal
launch_codex_network() {
    local num_nodes=${1:-2}  # Default to 2 nodes if not specified
    local launch_mode=${2:-"regular"}  # Default to regular mode if not specified
    
    # Clean up any existing Codex data
    for i in $(seq 1 $num_nodes); do
        rm -rf "./codex-$i" "./codex-$i.log"
    done

    # Start node 1 (first node doesn't need bootstrap)
    launch_codex_node 1 8080 "" "" "$launch_mode"

    sleep 2

    # Get the SPR from the first node to use as bootstrap for other nodes
    export SPR=$(curl -s -XGET localhost:8080/api/codex/v1/debug/info | jq --raw-output .spr)
    echoerr "Bootstrap SPR is ${SPR}."
    
    # Start additional nodes (nodes 2 to num_nodes)
    for i in $(seq 2 $num_nodes); do
        local api_port=$((8080 + i - 1))
        local disc_port=$((8090 + i - 1))
        
        launch_codex_node "$i" "$api_port" "$disc_port" "$SPR" "$launch_mode"
    done
}

# Create a random file with specified block size and count
# Usage: create_file <block_size> <block_count>
create_file() {
    local block_size=$1
    local block_count=$2
    local output_file="/tmp/testfile"
    
    echoerr "Creating file with block size: ${block_size}, block count: ${block_count}"
    dd if=/dev/urandom of=${output_file} bs=${block_size} count=${block_count} &> /dev/null
    echo ${output_file}
}

# Upload a file to a specified node
# Usage: upload <node_index> <file_path>
# Returns: Content ID (CID) of the uploaded file
upload() {
    local node_index=$1
    local file_path=$2
    local api_port=$((8080 + node_index - 1))
    
    echoerr "Uploading file to node ${node_index} (port: ${api_port})"
    local cid=$(curl -s -X POST -T "${file_path}" http://localhost:${api_port}/api/codex/v1/data)
    echo ${cid}
}

# Download a file from a specified node
# Usage: download <node_index> <cid>
download() {
    local node_index=$1
    local cid=$2
    local api_port=$((8080 + node_index - 1))
    
    echoerr "Downloading file from node ${node_index} (port: ${api_port})"
    curl -s -X GET "http://localhost:${api_port}/api/codex/v1/data/${cid}/network/stream" > /dev/null
}
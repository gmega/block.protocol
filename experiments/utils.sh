#!/usr/bin/env bash
#
# Utility functions for experiment scripts
#

export UTILS_TEMP="${UTILS_TEMP:-/tmp}"

# Array to store process IDs
declare -a PIDS=()

store_last_exit_code() {
    store_exit_code "$?"
}

# Stores the exit code for the current process
store_exit_code() {
    # Sadly, this is not portable at all.
    echo "$1" >"${UTILS_TEMP}/exit_code_${BASHPID}.pid"
}

# Add a process ID to the tracking list
track_process() {
    echo "$1" >"${UTILS_TEMP}/monitor_pids_$$"
}

# Track the most recently started background process
track_last_process() {
    track_process $!
}

# Cleanup function to kill all tracked processes
cleanup() {
    local pgid=$1
    echo_procmon "Cleaning up processes..."
    rm -rf "${UTILS_TEMP}/monitor_pids_$$"
    rm -rf "${UTILS_TEMP}/exit_code_*.pid"
    # Blasts the whole process group.
    kill -TERM -"${pgid}"
}

poll_queue() {
    while true; do
        if read -r -t 1 -u 3 new_pid; then
            PIDS+=("$new_pid")
            echo_procmon "Monitoring new PID ${pid}"
            continue
        else
            break
        fi
    done
}

# Fires a background process that monitors tracked processes, and
# kills both the parent and all tracked processes if any of them die
# with a failure.
monitor_processes() {
    parent_pid=$$
    export parent_pid
    parent_gid=$(ps -o pgid= -p "${parent_pid}" | sed 's/ //g')
    export parent_gid
    (
        set -e

        # Opens pipe in subshell, assigns to FD 3.
        echo_procmon "Start process monitor"
        exec 3<"${UTILS_TEMP}/monitor_pids_$$"

        shutdown="false"

        while [ "${shutdown}" = "false" ]; do
            poll_queue

            for pid in "${PIDS[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    continue
                fi
                echo_procmon "Process $pid died."

                if [ "${pid}" = "${parent_pid}" ]; then
                    echo_procmon "It was the parent process. Shutting down."
                    shutdown="true"
                    break
                fi

                echo_procmon "Checking exit code for $pid"
                if [ ! -f "${UTILS_TEMP}/exit_code_${pid}.pid" ]; then
                    echo_procmon "Error: no exit code found at ${UTILS_TEMP}/${pid}.pid. Shutting down."
                    shutdown="true"
                    break
                fi

                exit_code=$(cat "${UTILS_TEMP}/exit_code_${pid}.pid")
                if [ "$exit_code" -ne 0 ]; then
                    echo_procmon "Process $pid failed with exit code $exit_code. Shutting down."
                    shutdown="true"
                    break
                else
                    echo_procmon "Process $pid completed successfully"
                    PIDS=("${PIDS[@]/$pid/}")
                fi
            done
            sleep 1
        done

        echo_procmon "Cleanup and shut down monitor loop."
        poll_queue # makes sure to read everything before shutting down the pipe
        exec 3<&-
        echo_procmon "Kill process group $parent_gid."
        cleanup "$parent_gid"
        # After cleanup, we'll be dead.
    ) &
}

# Set up process tracking and cleanup
setup_process_tracking() {
    mkdir -p "${UTILS_TEMP}"
    mkfifo "${UTILS_TEMP}/monitor_pids_$$"
    monitor_processes
    track_process $$
}

# Print error message to stderr
echoerr() { echo "$@" 1>&2; }

echo_procmon() {
    echoerr "[Process Monitor]: $1"
}
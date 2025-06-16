#!/usr/bin/env bash
#
# Utility functions for experiment scripts
#

export UTILS_TEMP="${UTILS_TEMP:-/tmp}"

mkdir -p "${UTILS_TEMP}"

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
    echoerr "Track process $1"
    echo "$1" >"${UTILS_TEMP}/monitor_pids_$$"
}

# Track the most recently started background process
track_last_process() {
    track_process $!
}

# Cleanup function to kill all tracked processes
cleanup() {
    echoerr "Cleaning up processes..."
    for pid in "${PIDS[@]}"; do
        echoerr "Killing process $pid"
        if ps -p "$pid" >/dev/null; then
            kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
        fi
    done
    rm -rf "${UTILS_TEMP}/monitor_pids_$$"
    rm -rf "${UTILS_TEMP}/exit_code_*.pid"
}

# Fires a background process that monitors tracked processes, and
# kills both the parent and all tracked processes if any of them die
# with a failure.
monitor_processes() {
    parent_pid=$$
    export parent_pid
    (
        set -e

        # Opens pipe in subshell, assigns to FD 3.
        echoerr "Start process monitor"
        exec 3<"${UTILS_TEMP}/monitor_pids_$$"

        shutdown="false"

        while [ "${shutdown}" = "false" ]; do
            if read -r -t 1 -u 3 new_pid; then
                echoerr "Track process $new_pid"
                PIDS+=("$new_pid")
            fi
            for pid in "${PIDS[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    continue
                fi
                echoerr "Process $pid died."

                if [ "${pid}" = "${parent_pid}" ]; then
                    echoerr "It was the parent process. Shutting down."
                    shutdown="true"
                    break
                fi

                echoerr "Checking exit code for $pid"
                if [ ! -f "${UTILS_TEMP}/exit_code_${pid}.pid" ]; then
                    echoerr "Error: no exit code found at ${UTILS_TEMP}/${pid}.pid. Shutting down."
                    shutdown="true"
                    break
                fi

                exit_code=$(cat "${UTILS_TEMP}/exit_code_${pid}.pid")
                if [ "$exit_code" -ne 0 ]; then
                    echoerr "Process $pid failed with exit code $exit_code. Shutting down."
                    shutdown="true"
                    break
                else
                    echoerr "Process $pid completed successfully"
                    PIDS=("${PIDS[@]/$pid/}")
                fi
            done
            sleep 1
        done

        echoerr "Kill parent."
        kill -TERM "${parent_pid}" || true
        echoerr "Cleanup and shut down monitor loop."
        exec 3<&-
        cleanup
        echo "Done."
    ) &
}

# Set up process tracking and cleanup
setup_process_tracking() {
    mkfifo "${UTILS_TEMP}/monitor_pids_$$"
    monitor_processes
    track_process $$
}

# Print error message to stderr
echoerr() { echo "$@" 1>&2; }

#!/bin/bash
# =============================================================================
# QDomyos-Zwift: Universal Docker Build & Package Script (v3.4 - FINAL)
#
# This script builds the QDomyos-Zwift application and its ANT+ plugin for a
# specified target architecture using a containerized Docker environment.
#
# It produces a final, distributable tarball and includes intelligent,
# time-based cache pruning to manage disk space effectively.
#
# USAGE:
#   From the 'src' directory, run:
#   ./docker-build.sh --arch <ARCH>
#
# ARCH can be: arm64, x86_64
#
# Contributor(s): bassai-sho
# AI analysis tools (Claude, Gemini) were used to assist coding and debugging
# =============================================================================

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# --- Color Definitions for Logging ---
C_GREEN="\033[0;32m"
C_RED="\033[0;31m"
C_YELLOW="\033[0;33m"
C_BLUE="\033[0;34m"
C_RESET="\033[0m"

# --- Helper Functions for Logging ---
err() { echo -e "\n${C_RED}✗ ERROR: $*${C_RESET}" >&2; exit 1; }
info() { echo -e "${C_BLUE}>>> $*${C_RESET}"; }
warn() { echo -e "${C_YELLOW}⚠ WARNING: $*${C_RESET}" >&2; }
success() { echo -e "${C_GREEN}✓ SUCCESS:${C_RESET} $*"; }
format_duration() {
    local s=$1; printf "%d:%02d:%02d" $((s/3600)) $((s%3600/60)) $((s%60))
}

# ---
# SCRIPT LOGIC
# ---
show_usage() {
    echo "QDomyos-Zwift Universal Docker Build Script"
    echo "------------------------------------------"
    echo "Usage: $0 --arch <ARCHITECTURE>"
    echo ""
    echo "Required Arguments:"
    echo "  --arch <ARCH>   Specify the target architecture. Supported values:"
    echo "                    arm64   - For Raspberry Pi (ARM 64-bit)"
    echo "                    x86_64  - For Desktop Linux (Intel/AMD 64-bit)"
}

# This function handles Docker daemon and plugin verification and startup.
setup_and_verify_docker() {
    info "Verifying Docker environment..."

    if ! command -v docker >/dev/null 2>&1; then
        err "Docker is not installed. Please install Docker and re-run."
    fi

    if ! docker info >/dev/null 2>&1; then
        info "Docker daemon is not running. Attempting to start it..."
        if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
            sudo systemctl start docker
        elif command -v service >/dev/null 2>&1; then
             sudo service docker start
        else
            err "Could not determine how to start the Docker service. Please start it manually."
        fi
        sleep 5
        if ! docker info >/dev/null 2>&1; then
            err "Failed to start the Docker daemon."
        fi
        success "Docker daemon started successfully."
    fi

    if ! docker buildx version >/dev/null 2>&1; then
        err "Docker 'buildx' plugin is missing. Please reinstall Docker."
    fi

    success "Docker environment is correctly configured."
}

# For cross-compilation, ensures the necessary QEMU emulators are registered.
setup_qemu_if_needed() {
    info "Verifying QEMU for ARM64 cross-compilation..."
    if ! ls /proc/sys/fs/binfmt_misc/ | grep -q 'qemu-aarch64'; then
        warn "QEMU emulator for ARM64 not registered. Attempting automatic registration..."
        if docker run --rm --privileged multiarch/qemu-user-static --reset -p yes >/dev/null 2>&1; then
            success "QEMU has been successfully registered for this session."
        else
            err "Failed to register QEMU. Cannot proceed with the cross-platform build."
        fi
    else
        success "QEMU is correctly registered."
    fi
}

# ---
# MAIN FUNCTION
# ---
main() {
    local ARCH=""
    if [[ $# -eq 0 ]]; then show_usage; err "No architecture specified."; fi

    # Parse command-line arguments.
    while [[ $# -gt 0 ]]; do case $1 in --arch) ARCH="$2"; shift 2 ;; -h|--help) show_usage; exit 0 ;; *) err "Unknown option: $1" ;; esac; done

    # Run setup and verification checks first.
    setup_and_verify_docker

    local DOCKERFILE_PATH=""
    local PLATFORM_FLAG=""
    
    info "Preparing build for architecture: $ARCH"
    case "$ARCH" in
        "arm64")
            DOCKERFILE_PATH="../docker/rpi-ant/Dockerfile"
            PLATFORM_FLAG="--platform linux/arm64"
            setup_qemu_if_needed
            ;;
        "x86_64")
            DOCKERFILE_PATH="../docker/linux-ant/Dockerfile"
            PLATFORM_FLAG=""
            ;;
        *)
            err "Unsupported architecture '$ARCH'. Use 'arm64' or 'x86_64'."
            ;;
    esac

    if [[ ! -f "$DOCKERFILE_PATH" ]]; then err "Dockerfile not found at: $DOCKERFILE_PATH"; fi

    local SCRIPT_START_TIME=$(date +%s)
    local IMAGE_TAG="qdomyos-zwift-builder:$ARCH"
    
    # --- Final Naming Strategy ---
    local INTERNAL_EXEC_NAME="qdomyos-zwift"
    local INTERNAL_PLUGIN_NAME="libqz_ant.so"
    local OUTPUT_PACKAGE_NAME="qdomyos-zwift-${ARCH}.tar.gz"

    # --- Build Stage ---
    info "Starting Docker build using $DOCKERFILE_PATH (leveraging cache)..."
    if ! docker buildx build --progress=auto $PLATFORM_FLAG -t "$IMAGE_TAG" -f "$DOCKERFILE_PATH" --load ..; then
        err "Docker build failed. Please check the output above."
    fi
    success "Docker image built and loaded successfully."

    # --- Packaging Stage ---
    info "Extracting and packaging the compiled binaries..."
    
    local TMP_DIR="dist_package"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    
    local CONTAINER_ID
    CONTAINER_ID=$(docker create "$IMAGE_TAG")

    # In one command, copy the entire contents of the '/dist' directory
    # from the final container stage to our local staging directory.
    # The trailing '/.' on the source path is important.
    if ! docker cp "$CONTAINER_ID:/dist/." "$TMP_DIR/"; then
        docker rm -f "$CONTAINER_ID" >/dev/null
        err "Failed to copy artifacts from the Docker container."
    fi

    docker rm -f "$CONTAINER_ID" >/dev/null

    # 1. Define the name of the parent directory that will be inside the tarball.
    local PACKAGE_DIR_NAME="qz"
    
    # 2. Create a new, clean staging area.
    local STAGING_DIR="staging"
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR/$PACKAGE_DIR_NAME"
    
    # 3. Move all the extracted artifacts into the new parent directory.
    mv "$TMP_DIR"/* "$STAGING_DIR/$PACKAGE_DIR_NAME/"
    rm -rf "$TMP_DIR"
    
    # 4. Make the main executable runnable within its new location.
    chmod +x "$STAGING_DIR/$PACKAGE_DIR_NAME/qdomyos-zwift"
    
    info "Creating distributable package: $OUTPUT_PACKAGE_NAME"
    # 5. Create the final tarball.
    #    -C "$STAGING_DIR" : Change to the 'staging' directory.
    #    "$PACKAGE_DIR_NAME": Archive only the 'qdomyos-zwift' directory inside it.
    tar -czf "$OUTPUT_PACKAGE_NAME" -C "$STAGING_DIR" "$PACKAGE_DIR_NAME"
    
    # 6. Clean up the final staging directory.
    rm -rf "$STAGING_DIR"

    # --- Post-Build Cleanup Stage ---
    info "Cleaning up old Docker build cache (older than 72 hours)..."
    if docker builder prune --filter "until=72h" --force; then
        success "Old build cache pruned successfully."
    else
        warn "Could not prune Docker build cache. This is non-fatal."
    fi

    local SCRIPT_END_TIME=$(date +%s)
    local TOTAL_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
    
    # --- Final Output ---
    echo
    success "BUILD COMPLETE!"
    echo "------------------------------------------"
    echo -e "  Architecture:   $ARCH"
    echo -e "  Total Time:     $(format_duration $TOTAL_TIME)"
    echo -e "  Output Package: $(realpath ./$OUTPUT_PACKAGE_NAME)"
    echo -e "  tar -xzvf $(realpath ./$OUTPUT_PACKAGE_NAME)"
    echo "------------------------------------------"
    warn "NOTE FOR WSL2 USERS: This script cleans old Docker cache, but does not"
    warn "shrink the WSL virtual disk (.vhdx). To reclaim disk space on Windows,"
    warn "you must still periodically run 'wsl --shutdown' and compact the disk."
    echo "------------------------------------------"
}

# ---
# Run the main function with all provided command-line arguments
# ---
main "$@"
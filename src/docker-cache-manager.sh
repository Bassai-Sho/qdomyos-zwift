#!/bin/bash
# =============================================================================
# Docker Build Cache Manager
# 
# This script helps manage Docker build cache to balance build speed with
# disk space usage on WSL2/limited disk environments.
#
# USAGE:
#   ./docker-cache-manager.sh [command]
#
# Commands:
#   status    - Show current cache usage
#   clean     - Remove old/unused cache (keeps last 24h)
#   deep      - Deep clean (removes everything, slower rebuilds)
#   help      - Show this help
# =============================================================================

set -euo pipefail

C_GREEN="\033[0;32m"
C_RED="\033[0;31m"
C_YELLOW="\033[0;33m"
C_BLUE="\033[0;34m"
C_RESET="\033[0m"

info() { echo -e "${C_BLUE}>>> $*${C_RESET}"; }
success() { echo -e "${C_GREEN}✓ $*${C_RESET}"; }
warn() { echo -e "${C_YELLOW}⚠ $*${C_RESET}"; }

show_help() {
    echo "Docker Build Cache Manager"
    echo "=========================="
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  status    Show current cache usage and statistics"
    echo "  clean     Remove old/unused cache (keeps last 24h for fast rebuilds)"
    echo "  deep      Deep clean - removes ALL cache (next build will be slow)"
    echo "  help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 status    # Check how much space cache is using"
    echo "  $0 clean     # Safe cleanup, preserves recent cache"
    echo "  $0 deep      # Emergency cleanup when disk is full"
}

show_status() {
    info "Docker Build Cache Status"
    echo ""
    
    # Build cache
    echo "Build Cache:"
    docker buildx du || docker builder prune --dry-run --all --force 2>/dev/null || echo "  Unable to query build cache"
    echo ""
    
    # Images
    echo "Images:"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "(qdomyos|REPOSITORY)" || echo "  No QDomyos images"
    echo ""
    
    # Overall Docker disk usage
    echo "Overall Docker Disk Usage:"
    docker system df
    echo ""
    
    # WSL2 disk usage (if applicable)
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "WSL2 Virtual Disk:"
        df -h / | grep -E "(Filesystem|/)"
    fi
}

clean_cache() {
    info "Performing safe cache cleanup (keeps last 24h)..."
    echo ""
    
    # Remove old build cache (keeps last 24h for fast rebuilds)
    info "Removing build cache older than 24 hours..."
    if docker builder prune --filter "until=24h" --force; then
        success "Old build cache removed"
    fi
    echo ""
    
    # Remove dangling images (untagged, not used by any container)
    info "Removing dangling images..."
    if docker image prune --force; then
        success "Dangling images removed"
    fi
    echo ""
    
    # Remove stopped containers
    info "Removing stopped containers..."
    if docker container prune --force; then
        success "Stopped containers removed"
    fi
    echo ""
    
    success "Safe cleanup complete! Build cache from last 24h preserved for fast rebuilds."
    echo ""
    show_status
}

deep_clean() {
    warn "Deep clean will remove ALL Docker build cache!"
    warn "Your next build will be MUCH slower as it rebuilds everything."
    echo ""
    read -p "Are you sure? (type 'yes' to confirm): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo "Cancelled."
        exit 0
    fi
    
    info "Performing deep clean..."
    echo ""
    
    # Remove ALL build cache
    info "Removing ALL build cache..."
    if docker builder prune --all --force; then
        success "All build cache removed"
    fi
    echo ""
    
    # Remove unused images (not just dangling)
    info "Removing all unused images..."
    if docker image prune --all --force; then
        success "Unused images removed"
    fi
    echo ""
    
    # Remove stopped containers
    info "Removing stopped containers..."
    if docker container prune --force; then
        success "Stopped containers removed"
    fi
    echo ""
    
    # Remove unused volumes
    info "Removing unused volumes..."
    if docker volume prune --force; then
        success "Unused volumes removed"
    fi
    echo ""
    
    success "Deep clean complete!"
    warn "Next build will take longer as cache was cleared."
    echo ""
    show_status
}

main() {
    local command="${1:-help}"
    
    case "$command" in
        status)
            show_status
            ;;
        clean)
            clean_cache
            ;;
        deep)
            deep_clean
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
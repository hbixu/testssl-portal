#!/bin/bash
# check-versions.sh - Check for available updates for testssl-portal components
#
# This script compares the currently pinned versions in build.sh against
# the latest available versions from Docker Hub and GitHub.
#
# Requirements: curl, jq (optional, for better JSON parsing)
# Usage: ./check-versions.sh
# Exit codes: 0 = all up to date, 1 = updates available

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SH="$SCRIPT_DIR/build.sh"

# Counters for summary
BASEIMAGE_UPDATES=0
GITHUB_UPDATES=0

# ==============================================================================
# Helper Functions
# ==============================================================================

extract_default() {
    local var_name="$1"
    grep "^DEFAULT_${var_name}=" "$BUILD_SH" 2>/dev/null | head -1 | sed 's/.*="\([^"]*\)".*/\1/' | sed "s/.*='\([^']*\)'.*/\1/"
}

version_compare() {
    if [[ "$1" == "$2" ]]; then
        echo "equal"
    else
        local sorted=$(printf '%s\n%s' "$1" "$2" | sort -V | head -1)
        if [[ "$sorted" == "$1" ]]; then
            echo "newer"
        else
            echo "older"
        fi
    fi
}

# ==============================================================================
# Read Current Versions from build.sh
# ==============================================================================

echo -e "${BLUE}=== Checking for updates ===${NC}"
echo "Reading current versions from build.sh..."
echo ""

if [[ ! -f "$BUILD_SH" ]]; then
    echo -e "${RED}ERROR: build.sh not found at $BUILD_SH${NC}"
    exit 1
fi

CURRENT_BASEIMAGE=$(extract_default "BASEIMAGE_VERSION")
CURRENT_TESTSSL=$(extract_default "TESTSSL_VERSION")

if [[ -z "$CURRENT_BASEIMAGE" ]]; then
    CURRENT_BASEIMAGE="bookworm-20250224-slim"
fi

if [[ -z "$CURRENT_TESTSSL" ]]; then
    CURRENT_TESTSSL="3.2"
fi

echo "Current versions:"
echo "  Base image:   debian:$CURRENT_BASEIMAGE"
echo "  testssl.sh:   $CURRENT_TESTSSL"
echo ""

# ==============================================================================
# Check Base Image (Docker Hub)
# ==============================================================================

echo -e "${BLUE}--- Base Image (Docker Hub) ---${NC}"
echo "Repository: https://hub.docker.com/_/debian"

check_debian_tags() {
    local current_tag="$1"
    
    # Parse current tag: bookworm-20250224-slim or bookworm-slim
    local current_release=""
    local current_date=""
    if [[ "$current_tag" =~ ^([a-z]+)-([0-9]{8})-slim$ ]]; then
        current_release="${BASH_REMATCH[1]}"
        current_date="${BASH_REMATCH[2]}"
        echo "  Current: debian:$current_tag (release: $current_release, date: $current_date)"
    elif [[ "$current_tag" =~ ^([a-z]+)-slim$ ]]; then
        current_release="${BASH_REMATCH[1]}"
        current_date="rolling"
        echo "  Current: debian:$current_tag (release: $current_release, rolling tag)"
    else
        echo -e "  ${YELLOW}WARNING: Unrecognized tag format: $current_tag${NC}"
        return
    fi
    
    # Fetch tags from Docker Hub
    local api_url="https://hub.docker.com/v2/repositories/library/debian/tags?page_size=100&name=${current_release}"
    local response=$(curl -sf "$api_url" 2>/dev/null || echo "")
    
    if [[ -z "$response" ]]; then
        echo -e "  ${YELLOW}WARNING: Could not fetch tags from Docker Hub${NC}"
        return
    fi
    
    # Extract dated slim tags for current release (e.g., bookworm-20250224-slim)
    local dated_tags=""
    if command -v jq &>/dev/null; then
        dated_tags=$(echo "$response" | jq -r '.results[].name' 2>/dev/null | grep -E "^${current_release}-[0-9]{8}-slim$" | sort -r)
    else
        dated_tags=$(echo "$response" | grep -oE "\"name\":\"${current_release}-[0-9]{8}-slim\"" | sed 's/"name":"//;s/"//' | sort -r)
    fi
    
    if [[ -z "$dated_tags" ]]; then
        echo -e "  ${YELLOW}WARNING: No dated tags found for $current_release${NC}"
        return
    fi
    
    local latest_dated=$(echo "$dated_tags" | head -1)
    local latest_date=$(echo "$latest_dated" | sed "s/${current_release}-//;s/-slim//")
    
    # Compare dates
    if [[ "$current_date" == "rolling" ]]; then
        echo -e "  ${YELLOW}Using rolling tag. Latest pinned: $latest_dated${NC}"
        echo -e "  ${YELLOW}Recommendation: Pin to $latest_dated for reproducible builds${NC}"
        BASEIMAGE_UPDATES=1
    elif [[ "$current_date" == "$latest_date" ]]; then
        echo -e "  Same release ($current_release): ${GREEN}$current_tag (up to date)${NC}"
    elif [[ "$current_date" < "$latest_date" ]]; then
        echo -e "  Same release ($current_release): current $current_tag → latest $latest_dated ${YELLOW}(NEWER)${NC}"
        BASEIMAGE_UPDATES=1
    else
        echo -e "  Same release ($current_release): ${GREEN}$current_tag (up to date)${NC}"
    fi
    
    # Check for new release lines (e.g., trixie if on bookworm)
    local all_releases=""
    api_url="https://hub.docker.com/v2/repositories/library/debian/tags?page_size=100&name=slim"
    response=$(curl -sf "$api_url" 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        if command -v jq &>/dev/null; then
            all_releases=$(echo "$response" | jq -r '.results[].name' 2>/dev/null | grep -E "^[a-z]+-slim$" | sed 's/-slim$//' | sort -u)
        else
            all_releases=$(echo "$response" | grep -oE '"name":"[a-z]+-slim"' | sed 's/"name":"//;s/-slim"//' | sort -u)
        fi
        
        if [[ -n "$all_releases" ]]; then
            echo "  Available releases: $(echo "$all_releases" | tr '\n' ', ' | sed 's/,$//')"
        fi
    fi
}

check_debian_tags "$CURRENT_BASEIMAGE"
echo ""

# ==============================================================================
# Check testssl.sh (GitHub)
# ==============================================================================

echo -e "${BLUE}--- GitHub Components ---${NC}"

check_github_release() {
    local owner="$1"
    local repo="$2"
    local current="$3"
    local name="$4"
    
    echo "$name (https://github.com/$owner/$repo)"
    
    local api_url="https://api.github.com/repos/$owner/$repo/releases/latest"
    local response=$(curl -sf "$api_url" 2>/dev/null || echo "")
    
    if [[ -z "$response" ]]; then
        api_url="https://api.github.com/repos/$owner/$repo/tags"
        response=$(curl -sf "$api_url" 2>/dev/null || echo "")
        
        if [[ -z "$response" ]]; then
            echo -e "  ${YELLOW}WARNING: Could not fetch releases/tags from GitHub${NC}"
            return
        fi
        
        if command -v jq &>/dev/null; then
            latest=$(echo "$response" | jq -r '.[0].name' 2>/dev/null)
        else
            latest=$(echo "$response" | grep -oE '"name":"[^"]*"' | head -1 | sed 's/"name":"//;s/"//')
        fi
    else
        if command -v jq &>/dev/null; then
            latest=$(echo "$response" | jq -r '.tag_name' 2>/dev/null)
        else
            latest=$(echo "$response" | grep -oE '"tag_name":"[^"]*"' | sed 's/"tag_name":"//;s/"//')
        fi
    fi
    
    if [[ -z "$latest" || "$latest" == "null" ]]; then
        echo -e "  ${YELLOW}WARNING: Could not determine latest version${NC}"
        return
    fi
    
    local latest_clean=$(echo "$latest" | sed 's/^v//')
    local current_clean=$(echo "$current" | sed 's/^v//')
    
    if [[ "$current_clean" == "$latest_clean" || "$current" == "$latest" ]]; then
        echo -e "  current $current → latest $latest ${GREEN}(up to date)${NC}"
    else
        local cmp=$(version_compare "$current_clean" "$latest_clean")
        if [[ "$cmp" == "newer" ]]; then
            echo -e "  current $current → latest $latest ${YELLOW}(NEWER)${NC}"
            GITHUB_UPDATES=$((GITHUB_UPDATES + 1))
        else
            echo -e "  current $current → latest $latest ${GREEN}(up to date)${NC}"
        fi
    fi
}

check_github_release "testssl" "testssl.sh" "$CURRENT_TESTSSL" "testssl.sh"
echo ""

# ==============================================================================
# Summary
# ==============================================================================

echo -e "${BLUE}=== Summary ===${NC}"

TOTAL_UPDATES=$((BASEIMAGE_UPDATES + GITHUB_UPDATES))

if [[ $BASEIMAGE_UPDATES -gt 0 ]]; then
    echo -e "${YELLOW}A new base image line is available (consider migrating).${NC}"
fi

if [[ $GITHUB_UPDATES -gt 0 ]]; then
    echo -e "${YELLOW}$GITHUB_UPDATES GitHub component(s) have newer versions.${NC}"
fi

if [[ $TOTAL_UPDATES -eq 0 ]]; then
    echo -e "${GREEN}All components are up to date.${NC}"
    exit 0
else
    echo ""
    echo "Consider updating build.sh and releasing a new image."
    exit 1
fi

#!/bin/bash

# Build script for testssl-portal Docker image

set -e

# ============================================================================
# DEFAULT VALUES - Edit these to change defaults
# ============================================================================
DEFAULT_VERSION="1.0.0"

# Base image: https://hub.docker.com/_/debian/tags?name=bookworm
# Check versions: ./check-versions.sh or browse Docker Hub tags
# Format: bookworm-YYYYMMDD-slim (pinned) or bookworm-slim (rolling)
DEFAULT_BASEIMAGE_VERSION="bookworm-20250224-slim"

# testssl.sh: https://github.com/testssl/testssl.sh/releases
# Check versions: curl -s https://api.github.com/repos/testssl/testssl.sh/releases/latest | grep tag_name
# Or run: ./check-versions.sh
DEFAULT_TESTSSL_VERSION="v3.2.3"   # Branch or tag (e.g. 3.2, v3.2.5, main)

DEFAULT_PLATFORMS="native"      # native | linux/amd64 | linux/arm64 | linux/amd64,linux/arm64
DEFAULT_BUILDER_NAME="testssl-portal-builder"
DEFAULT_REGISTRY=""             # Empty for local build; e.g. docker.io/username for Docker Hub
DEFAULT_IMAGE_NAME="testssl-portal"
# ============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_help() {
    cat << EOF
testssl-portal - Docker build script

Usage: $0 [OPTIONS]

Options:
    -h, --help                  Show this help message
    --version VERSION           Image version/tag (default: $DEFAULT_VERSION)
    --baseimage-version VER     Debian base image tag (default: $DEFAULT_BASEIMAGE_VERSION)
    --testssl-version VER       testssl.sh branch or tag (default: $DEFAULT_TESTSSL_VERSION)
    --platform PLATFORM         Target platform(s) (default: $DEFAULT_PLATFORMS)
                                Use 'native' for current platform only
                                Examples: linux/amd64 | linux/arm64 | linux/amd64,linux/arm64
    --registry REGISTRY         Registry prefix (e.g. docker.io/username for Docker Hub)
    --image-name NAME           Image name (default: $DEFAULT_IMAGE_NAME)
    --push                      Push image to registry after build (requires --registry and docker login)
    --local                     Build locally only, do not push (default)
    --no-cache                  Build without using cache

Environment Variables:
    BUILD_DATE              Build date (auto-generated if not set, format: %Y-%m-%dT%H:%M:%SZ)
    VERSION                 Image version (used for tag and build-arg)
    BASEIMAGE_VERSION       Debian base image tag
    TESTSSL_VERSION         testssl.sh branch or tag to build
    PLATFORMS               Target platform(s)
    REGISTRY                Registry prefix
    IMAGE_NAME              Image name

Build Modes:
    1. Local build (default):   $0
    2. Push to registry:        $0 --registry docker.io/username --push

Examples:
    chmod +x build.sh
    $0 --help                    # See all options

    # Local build (default)
    $0
    $0 --local

    # Build with specific testssl.sh version
    $0 --testssl-version v3.2.5

    # Build for linux/amd64 and linux/arm64 and push to Docker Hub (using env vars)
    VERSION=1.0.0 TESTSSL_VERSION=v3.2.3 $0 --registry docker.io/username --platform linux/amd64,linux/arm64 --push

    # Same with options instead of env vars
    $0 --version 1.0.0 --testssl-version v3.2.3 --registry docker.io/username --platform linux/amd64,linux/arm64 --push

Note: Default values can be changed at the top of this script.

EOF
}

PLATFORMS="${PLATFORMS:-$DEFAULT_PLATFORMS}"
PUSH=false
NO_CACHE=""
REGISTRY="${REGISTRY:-$DEFAULT_REGISTRY}"
IMAGE_NAME="${IMAGE_NAME:-$DEFAULT_IMAGE_NAME}"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --baseimage-version)
            BASEIMAGE_VERSION="$2"
            shift 2
            ;;
        --testssl-version)
            TESTSSL_VERSION="$2"
            shift 2
            ;;
        --platform)
            PLATFORMS="$2"
            shift 2
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --image-name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --local)
            PUSH=false
            shift
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

VERSION="${VERSION:-$DEFAULT_VERSION}"
BASEIMAGE_VERSION="${BASEIMAGE_VERSION:-$DEFAULT_BASEIMAGE_VERSION}"
TESTSSL_VERSION="${TESTSSL_VERSION:-$DEFAULT_TESTSSL_VERSION}"
BUILD_DATE="${BUILD_DATE:-$(date -u +'%Y-%m-%dT%H:%M:%SZ')}"

if [ "$PUSH" = true ] && [ -z "$REGISTRY" ]; then
    echo -e "${YELLOW}ERROR: --push requires --registry${NC}"
    echo "Example: $0 --registry docker.io/username --platform linux/amd64,linux/arm64 --push"
    exit 1
fi

# Resolve script dir and project root (parent of script dir if script is in repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}=== Building testssl-portal ===${NC}"
echo "Build date:       $BUILD_DATE"
echo "Version:          $VERSION"
echo "Base image:       debian:$BASEIMAGE_VERSION"
echo "testssl.sh:       $TESTSSL_VERSION"
echo "Image name:       $IMAGE_NAME"
echo "Platform(s):      $PLATFORMS"
if [ -n "$REGISTRY" ]; then
    REGISTRY="${REGISTRY%/}"
    echo "Registry:     $REGISTRY"
    FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}"
else
    FULL_IMAGE="$IMAGE_NAME"
fi
if [ "$PUSH" = true ]; then
    echo -e "Push:         ${GREEN}yes${NC}"
else
    echo -e "Push:         no${NC}"
fi
echo ""

BUILD_ARGS=(
    --build-arg "BUILD_DATE=$BUILD_DATE"
    --build-arg "VERSION=$VERSION"
    --build-arg "BASEIMAGE_VERSION=$BASEIMAGE_VERSION"
    --build-arg "TESTSSL_VERSION=$TESTSSL_VERSION"
)

TAGS=(
    -t "${FULL_IMAGE}:${VERSION}"
    -t "${FULL_IMAGE}:latest"
)

# Optional: also tag short name when using registry (for local load)
if [ -n "$REGISTRY" ] && [ "$PUSH" = false ]; then
    TAGS+=(
        -t "${IMAGE_NAME}:${VERSION}"
        -t "${IMAGE_NAME}:latest"
    )
fi

if [ "$PLATFORMS" = "native" ]; then
    echo -e "${BLUE}Building for native platform...${NC}"
    docker build \
        "${BUILD_ARGS[@]}" \
        "${TAGS[@]}" \
        $NO_CACHE \
        .
    echo ""
    echo -e "${GREEN}=== Build complete ===${NC}"
    echo "Tags: ${FULL_IMAGE}:${VERSION}, ${FULL_IMAGE}:latest"
else
    if ! docker buildx version > /dev/null 2>&1; then
        echo -e "${YELLOW}ERROR: Multi-platform build requires docker buildx${NC}"
        echo "Use --platform native for a local build, or install buildx."
        exit 1
    fi
    BUILDER_NAME="$DEFAULT_BUILDER_NAME"
    if ! docker buildx ls | grep -q "$BUILDER_NAME"; then
        echo -e "${BLUE}Creating buildx builder: $BUILDER_NAME${NC}"
        docker buildx create --name "$BUILDER_NAME" --use
    else
        docker buildx use "$BUILDER_NAME" 2>/dev/null || true
    fi
    docker buildx inspect --bootstrap > /dev/null 2>&1 || true

    if echo "$PLATFORMS" | grep -q "," && [ "$PUSH" = false ]; then
        echo -e "${YELLOW}Multi-platform builds cannot be loaded locally. Use --push with --registry.${NC}"
        exit 1
    fi

    echo -e "${BLUE}Building for platform(s): $PLATFORMS${NC}"
    if [ "$PUSH" = true ]; then
        docker buildx build \
            --platform "$PLATFORMS" \
            "${BUILD_ARGS[@]}" \
            "${TAGS[@]}" \
            $NO_CACHE \
            --push \
            .
        echo ""
        echo -e "${GREEN}=== Build and push complete ===${NC}"
        echo "Pushed: ${FULL_IMAGE}:${VERSION}, ${FULL_IMAGE}:latest"
    else
        docker buildx build \
            --platform "$PLATFORMS" \
            "${BUILD_ARGS[@]}" \
            "${TAGS[@]}" \
            $NO_CACHE \
            --load \
            .
        echo ""
        echo -e "${GREEN}=== Build complete ===${NC}"
        echo "Tags: ${FULL_IMAGE}:${VERSION}, ${FULL_IMAGE}:latest"
    fi
fi

echo ""
echo "Run: docker run --rm -p 5000:5000 ${FULL_IMAGE}:${VERSION}"

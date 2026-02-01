#!/bin/bash
set -e

# Default values
DEFAULT_KEEP=10
DRY_RUN=false
ARTIFACT_PATH=""
KEEP_COUNT=""

# Help message
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Clean up old artifact runs from gh-pages branch.

Options:
    --help              Show this help message
    --dry-run           Preview what would be deleted without making changes
    --keep N            Number of recent runs to keep (default: from config.json or $DEFAULT_KEEP)
    --artifact-path P   Target a specific path (e.g., project/report-type)

Examples:
    $(basename "$0") --dry-run
    $(basename "$0") --keep 5
    $(basename "$0") --artifact-path heroes-of-talisman/playwright-report
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep)
            KEEP_COUNT="$2"
            shift 2
            ;;
        --artifact-path)
            ARTIFACT_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Configure git if in CI environment
if [[ -n "$GIT_USER_NAME" ]]; then
    git config user.name "$GIT_USER_NAME"
    git config user.email "$GIT_USER_EMAIL"
fi

# Find all project directories or use specified path
if [[ -n "$ARTIFACT_PATH" ]]; then
    SEARCH_PATHS=("$ARTIFACT_PATH")
else
    # Find all directories that contain numbered run folders
    SEARCH_PATHS=()
    while IFS= read -r -d '' dir; do
        # Check if directory contains numbered subdirectories
        if ls -d "$dir"/[0-9]* >/dev/null 2>&1; then
            SEARCH_PATHS+=("$dir")
        fi
    done < <(find . -mindepth 2 -maxdepth 2 -type d ! -path "./.git/*" ! -path "./scripts/*" -print0 2>/dev/null)
fi

PATHS_TO_DELETE=()

for artifact_dir in "${SEARCH_PATHS[@]}"; do
    # Skip if directory doesn't exist
    [[ -d "$artifact_dir" ]] || continue

    # Get keep count from config.json or use default
    project_dir=$(dirname "$artifact_dir")
    config_file="$project_dir/config.json"

    if [[ -n "$KEEP_COUNT" ]]; then
        keep=$KEEP_COUNT
    elif [[ -f "$config_file" ]] && command -v jq &> /dev/null; then
        keep=$(jq -r '.keep // empty' "$config_file" 2>/dev/null || echo "")
        [[ -z "$keep" ]] && keep=$DEFAULT_KEEP
    else
        keep=$DEFAULT_KEEP
    fi

    echo "Processing: $artifact_dir (keeping last $keep runs)"

    # Get all run directories, sorted numerically
    runs=()
    while IFS= read -r run; do
        runs+=("$run")
    done < <(ls -d "$artifact_dir"/[0-9]* 2>/dev/null | sort -t'/' -k3 -n -r)

    total=${#runs[@]}

    if [[ $total -le $keep ]]; then
        echo "  Found $total runs, keeping all (threshold: $keep)"
        continue
    fi

    # Mark runs for deletion (keep the most recent N)
    delete_count=$((total - keep))
    echo "  Found $total runs, will delete $delete_count oldest"

    for ((i = keep; i < total; i++)); do
        run_path="${runs[$i]}"
        echo "  - Will delete: $run_path"
        PATHS_TO_DELETE+=("$run_path")
    done
done

if [[ ${#PATHS_TO_DELETE[@]} -eq 0 ]]; then
    echo ""
    echo "Nothing to clean up."
    exit 0
fi

echo ""
echo "Total paths to delete: ${#PATHS_TO_DELETE[@]}"

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "[DRY RUN] No changes made."
    exit 0
fi

# Delete the directories
for path in "${PATHS_TO_DELETE[@]}"; do
    echo "Deleting: $path"
    rm -rf "$path"
done

# Commit the deletions
git add -A
git commit -m "chore: Clean up old artifact runs

Deleted ${#PATHS_TO_DELETE[@]} old artifact run(s)" || echo "Nothing to commit"

# Remove from git history using git-filter-repo with --partial to preserve origin remote
echo ""
echo "Removing deleted paths from git history..."

# Build the path filter arguments
FILTER_ARGS=()
for path in "${PATHS_TO_DELETE[@]}"; do
    # Remove leading ./ if present
    clean_path="${path#./}"
    FILTER_ARGS+=("--invert-paths" "--path" "$clean_path")
done

# Run git-filter-repo with --partial to preserve the origin remote
git filter-repo --partial --force "${FILTER_ARGS[@]}"

echo ""
echo "Cleanup complete!"

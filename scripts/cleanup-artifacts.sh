#!/usr/bin/env bash
set -e

# Cleanup old artifact runs from gh-pages branch
# Usage: ./cleanup-artifacts.sh [--artifact-path PATH] [--dry-run]

DEFAULT_KEEP=10
ARTIFACT_PATH=""
DRY_RUN="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --artifact-path)
      ARTIFACT_PATH="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--artifact-path PATH] [--dry-run]"
      echo ""
      echo "Options:"
      echo "  --artifact-path PATH  Target a specific path (e.g., heroes-of-talisman/playwright-report)"
      echo "  --dry-run             Preview what would be deleted without making changes"
      echo ""
      echo "Configuration:"
      echo "  Place a config.json in the project root (e.g., heroes-of-talisman/config.json)"
      echo "  with {\"keep\": N} to override the default retention count of $DEFAULT_KEEP"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Initialize paths file
PATHS_FILE=$(mktemp)
trap "rm -f $PATHS_FILE" EXIT

# Function to process a single artifact directory
process_artifact_dir() {
  local artifact_path="$1"
  local parent_dir=$(dirname "$artifact_path")
  local config_file="${parent_dir}/config.json"
  local keep_count=$DEFAULT_KEEP

  # Read config if exists
  if [ -f "$config_file" ]; then
    configured_keep=$(jq -r '.keep // empty' "$config_file" 2>/dev/null || true)
    if [ -n "$configured_keep" ] && [ "$configured_keep" -gt 0 ] 2>/dev/null; then
      keep_count=$configured_keep
      echo "Using configured keep count: $keep_count from $config_file"
    fi
  else
    echo "No config found at $config_file, using default: $keep_count"
  fi

  # Get all numeric subdirectories, sorted numerically descending
  local dirs_to_check="$artifact_path"
  if [ ! -d "$dirs_to_check" ]; then
    echo "Directory $dirs_to_check does not exist, skipping"
    return
  fi

  # Find numeric folders and sort numerically
  local all_runs=$(find "$dirs_to_check" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null | grep -E '^[0-9]+$' | sort -n -r)

  if [ -z "$all_runs" ]; then
    echo "No numeric run folders found in $artifact_path"
    return
  fi

  local total_count=$(echo "$all_runs" | wc -l | tr -d ' ')
  echo "Found $total_count run folders in $artifact_path"

  # Skip if we have fewer than keep_count
  if [ "$total_count" -le "$keep_count" ]; then
    echo "Total runs ($total_count) <= keep count ($keep_count), nothing to delete"
    return
  fi

  # Get folders to delete (all except the last keep_count)
  local to_delete=$(echo "$all_runs" | tail -n +$((keep_count + 1)))
  local delete_count=$(echo "$to_delete" | wc -l | tr -d ' ')

  echo "Will delete $delete_count old run folders, keeping newest $keep_count"

  for run_num in $to_delete; do
    local full_path="${artifact_path}/${run_num}"
    echo "  - $full_path"

    if [ "$DRY_RUN" != "true" ]; then
      # Remove from working tree
      rm -rf "$full_path"

      # Track path for git-filter-repo
      echo "$full_path" >> "$PATHS_FILE"
    fi
  done
}

# If specific path provided, process only that
if [ -n "$ARTIFACT_PATH" ]; then
  echo "Processing specified path: $ARTIFACT_PATH"
  process_artifact_dir "$ARTIFACT_PATH"
else
  # Auto-discover: find all directories that contain numeric subdirectories
  echo "Auto-discovering artifact directories..."

  # Find potential artifact paths (directories containing numeric subdirs)
  for potential_parent in $(find . -mindepth 2 -maxdepth 2 -type d -name '[0-9]*' 2>/dev/null | xargs -I {} dirname {} | sort -u); do
    # Remove leading ./
    clean_path="${potential_parent#./}"
    echo "Discovered artifact path: $clean_path"
    process_artifact_dir "$clean_path"
  done
fi

if [ "$DRY_RUN" = "true" ]; then
  echo ""
  echo "=== DRY RUN - No changes made ==="
  exit 0
fi

# Check if there are paths to filter
if [ ! -s "$PATHS_FILE" ]; then
  echo "No paths to clean from git history"
  exit 0
fi

echo ""
echo "=== Removing deleted paths from git history ==="

# Commit the deletions first
git config user.name "${GIT_USER_NAME:-cleanup-bot}"
git config user.email "${GIT_USER_EMAIL:-cleanup-bot@users.noreply.github.com}"

git add -A
if git diff --cached --quiet; then
  echo "No changes to commit"
else
  git commit -m "chore: cleanup old artifact runs"
fi

# Use git-filter-repo to remove paths from history
echo "Filtering the following paths from history:"
cat "$PATHS_FILE"

git filter-repo --invert-paths --paths-from-file "$PATHS_FILE" --force

echo ""
echo "=== Cleanup complete ==="
echo "Run 'git push origin gh-pages --force' to push changes"

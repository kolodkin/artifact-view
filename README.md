# Artifact View

A repository for hosting static HTML artifacts via GitHub Pages, extending GitHub's markdown summary capability with full HTML report support.

## Overview

GitHub Actions provides job summaries via markdown, but complex reports (like Playwright test reports, coverage reports, or other HTML-based outputs) require a hosted environment. This repository serves as a dedicated hosting solution for such artifacts.

Artifacts are organized by:
```
{project}/{report-type}/{run-number}/
```

For example:
```
heroes-of-talisman/playwright-report/97/
```

## Configuration

Each project can have a `config.json` file to customize cleanup behavior:

```
{project}/config.json
```

### Config Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `keep` | number | 10 | Number of recent runs to keep |

Example `config.json`:
```json
{
  "keep": 20
}
```

## Automatic Cleanup

A scheduled GitHub Action runs daily to clean up old artifact runs:

- Keeps the last `n` runs per project (configurable via `config.json`, default: 10)
- Sorts runs numerically (not lexicographically) to ensure correct ordering
- Removes deleted artifacts from git history using `git-filter-repo` to keep the repository size manageable

### Manual Cleanup

You can trigger cleanup manually via GitHub Actions:

1. Go to **Actions** > **Cleanup Old Artifacts**
2. Click **Run workflow**
3. Optionally specify:
   - `artifact_path`: Target a specific path (e.g., `heroes-of-talisman/playwright-report`)
   - `dry_run`: Preview what would be deleted without making changes

### Local Cleanup

Run the cleanup script locally for testing or manual cleanup:

```bash
# Prerequisites: jq, git-filter-repo
pip install git-filter-repo

# Checkout gh-pages branch
git checkout gh-pages

# Run cleanup
./scripts/cleanup-artifacts.sh --help
./scripts/cleanup-artifacts.sh --dry-run
./scripts/cleanup-artifacts.sh --keep 5              # override keep count
./scripts/cleanup-artifacts.sh
git push origin gh-pages --force
```

## Usage

To deploy artifacts to this repository from another workflow:

```yaml
- name: Deploy to Artifact View
  uses: peaceiris/actions-gh-pages@v3
  with:
    personal_token: ${{ secrets.ARTIFACT_VIEW_TOKEN }}
    external_repository: your-org/artifact-view
    publish_branch: gh-pages
    publish_dir: ./your-report-dir
    destination_dir: your-project/report-type/${{ github.run_number }}
```

## Branches

- `main`: Contains workflow definitions and documentation
- `gh-pages`: Hosts the static artifacts, cleanup script, and config (served via GitHub Pages)

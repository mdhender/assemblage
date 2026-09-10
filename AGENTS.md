# AGENTS.md

These instructions apply to the entire repository.

## Alpha workflow

- Work directly on `main`. Do not create branches while the project is in alpha.
- Agents are authorized to commit directly to `main` without asking for additional approval, provided the commit follows the versioning rules below.
- Agents are authorized to push compliant commits to the upstream repository without asking for additional approval.
- Assign every GitHub issue and pull request to `mdhender`.
- When work is associated with a GitHub issue, reference (and/or close) that issue in the commit message, for example: `Fixes #1`.
- Keep exactly one database migration file while the project is in alpha (edit that single migration for schema changes instead of creating additional migration files).

## Versioning

- Follow semantic versioning using the version declared in `version.go`.
- Every commit containing code changes must also bump the version in `version.go`:
  - Bump the patch version for backward-compatible fixes.
  - Bump the minor version for backward-compatible features or other new functionality.
- Never bump the version for documentation-only changes.
- Do not commit or push a code change unless its required version bump is included in the same commit.

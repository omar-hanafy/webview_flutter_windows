---
name: prepare-release
description: Use when preparing, executing, or debugging a release of webview_flutter_windows to pub.dev - version bumps, changelog entries, release PRs, tags, or the publish automation.
---

# Prepare a webview_flutter_windows release

Releases are automated behind a version-bump PR. Humans (or agents) only
bump versions, write the changelog, and merge; automation does the rest.
Never create tags manually, never move a tag, never run `dart pub publish`
locally, and never reuse a published version.

## Lanes

| Lane | Branch | Version shape | Result |
| --- | --- | --- | --- |
| Stable | `main` | `X.Y.Z` | Tag + GitHub release + pub.dev publish |
| Prerelease | `dev` | `X.Y.Z-dev.N` | Same, marked prerelease |

CI rejects a version that does not match the target lane's shape.

## Steps

1. **Decide the version** from the public delta since the last release tag
   (`git log $(git describe --tags --abbrev=0)..HEAD --oneline` on the
   lane). Patch: fixes/tooling/docs. Minor: new API. Major: breaking (needs
   a migration-guide section and, when nontrivial, a new versioned
   migration skill under `agent_plugins/webview-flutter-windows/skills/`).
2. **Branch** from the up-to-date lane head, e.g. `release-1.1.1`.
3. **Bump every version-bearing file to the same value**:
   - `pubspec.yaml` `version:`
   - `agent_plugins/webview-flutter-windows/.claude-plugin/plugin.json`
   - `agent_plugins/webview-flutter-windows/.codex-plugin/plugin.json`
   - the plugin entry in `.claude-plugin/marketplace.json`
   (`dart tool/validate_agent_plugin.dart` fails on any drift.)
4. **Changelog**: add a top `## X.Y.Z` section describing the user-visible
   delta with PR links, matching the existing entry style. No internal
   noise; call out breaking changes explicitly and link
   `migration_guide.md` when applicable.
5. **Run the full gate set** and fix root causes (never weaken lints or
   skip tests):

   ```sh
   dart format --output=none --set-exit-if-changed .
   flutter analyze
   flutter test
   (cd example && flutter analyze && flutter test)
   dart pub publish --dry-run          # inspect the file list
   dart tool/validate_agent_plugin.dart
   dart pub global activate pana 0.23.14 && pana --exit-code-threshold 0 .
   ```

   The dry-run file list must contain no `agent_plugins/`, `.claude*`,
   `.agents/`, `AGENTS.md`, `CLAUDE.md`, `tool/`, or `docs/` entries.
6. **PR to the lane branch** (`main` or `dev`). The labeler marks it
   `release` (it touches pubspec). CI must be fully green, including the
   Windows-native jobs.
7. **Merge.** On push, `auto-release.yml` detects the version change,
   creates tag `webview_flutter_windows-vX.Y.Z` at the merge commit
   (requires the `TAG_PUSH_PAT` secret), and creates the GitHub release;
   the tag push triggers `publish.yml`, which publishes to pub.dev via the
   dart-lang reusable workflow (OIDC trusted publishing; no local
   credentials).
8. **Verify**: both workflow runs green
   (`gh run list --workflow=auto-release.yml`, `--workflow="Publish to pub.dev"`),
   the tag exists at the merge commit, and
   `https://pub.dev/packages/webview_flutter_windows` shows the version
   (API: `https://pub.dev/api/packages/webview_flutter_windows`).

## Recovery

- Tag already exists pointing at a different commit: stop; that version is
  burned. Investigate; if needed, release the next patch version instead.
- `auto-release` succeeded but publish failed: fix the cause, then re-run
  the publish workflow run from the Actions UI (the tag already exists; do
  not recreate it).
- Published to pub.dev but something is wrong in it: you cannot unpublish;
  prepare the next patch release (use `dart pub` retraction only for
  serious problems, via pub.dev admin UI).

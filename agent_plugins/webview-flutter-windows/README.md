# webview-flutter-windows agent plugin

Package-specific skills that make AI coding agents (Claude Code and OpenAI
Codex) reliable when working with the
[`webview_flutter_windows`](https://pub.dev/packages/webview_flutter_windows)
Flutter package. The package's API is newer than most model training data;
these skills carry the exact contract so agents stop guessing.

The plugin is instructions-only: five skills with reference documents and
one copyable test helper. No hooks, no MCP servers, no executables, no
network access.

## Skills

| Skill | Use it for |
| --- | --- |
| `integrate-webview-windows` | Adding/embedding a WebView2 view: controller lifecycle, widget wiring, popups, context menus, permissions, headless mode, WebView2 Runtime detection. |
| `bridge-webview-windows` | Dart/JavaScript messaging, executeScript, bootstrap scripts, serving bundled/local content via virtual host mapping, cookies around login flows. |
| `troubleshoot-webview-windows` | Symptom-keyed diagnosis: blank views, init errors, focus/keyboard issues, missing menus, silent streams, NuGet/CMake/VS build failures. |
| `test-webview-windows` | Widget/unit tests without Windows: the exact channel fake, `tester.runAsync` rules, event injection. |
| `migrate-from-webview-windows` | Upgrading a project from upstream `webview_windows` 0.x to `webview_flutter_windows` 1.x (renames, broadcast streams, focus-workaround deletion, context-menu default). |

## Install

Claude Code (CLI or desktop):

```text
/plugin marketplace add omar-hanafy/webview_flutter_windows
/plugin install webview-flutter-windows@webview-flutter-windows
```

OpenAI Codex (CLI; also surfaces in the ChatGPT desktop app):

```sh
codex plugin marketplace add omar-hanafy/webview_flutter_windows
codex plugin add webview-flutter-windows@webview-flutter-windows
```

Start a new session after installing (Codex requires it; Claude Code can
`/reload-plugins` instead). Skills then activate automatically when a task
matches, or explicitly: `/webview-flutter-windows:migrate-from-webview-windows`
in Claude Code, `$migrate-from-webview-windows` in Codex.

## Layout

```text
.claude-plugin/plugin.json   Claude Code manifest
.codex-plugin/plugin.json    Codex manifest
skills/<name>/SKILL.md       One directory per skill (shared by both tools)
skills/<name>/references/    Progressive-disclosure references per skill
evals/<case>/prompt.md       Behavioral eval cases (+ graders/rubric.md)
```

Both manifests and both repo-root marketplace catalogs must carry the same
plugin version as the package's `pubspec.yaml`. `dart tool/validate_agent_plugin.dart`
(run from the repository root, also in CI) enforces that, plus frontmatter,
naming, path, and parity rules.

## Versioning

The plugin version always equals the `webview_flutter_windows` package
version it was released with. Skills document the 1.x API; the
`setDefaultContextMenusEnabled` API needs package `>=1.1.0`.

## For maintainers

Edit skills here (one directory per skill, `name` frontmatter matching the
directory), run `dart tool/validate_agent_plugin.dart`, then follow the
release flow in `.claude/skills/prepare-release/SKILL.md`. Behavioral eval
scenarios live in `evals/`; each has a prompt and a grader rubric with
MUST/SHOULD/FAIL criteria that double as manual smoke-test checklists.

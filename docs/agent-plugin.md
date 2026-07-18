# AI coding-assistant plugin

`webview_flutter_windows` ships package-specific support for AI coding
agents: an installable plugin for **Claude Code** and **OpenAI Codex**
containing five skills, distributed from this repository (never through the
pub.dev archive). The package itself gains no runtime AI features.

Why it exists: the package was first published in 2026, after most model
training cutoffs, so agents working from memory either refuse to touch it or
invent APIs (upstream `webview_windows` habits, `webview_flutter` idioms,
wrong channel contracts). The skills carry the exact 1.x contract, the
documented behavioral rules (broadcast streams, disabled-by-default context
menus, the focus invariant), and a test harness proven against the real
package.

## What is included

| Component | Activates when | Notable content |
| --- | --- | --- |
| `integrate-webview-windows` skill | Adding/embedding a webview, controller/widget wiring, popups, menus, permissions, headless mode, runtime detection | Canonical lifecycle, the three ordering rules, full API quick reference |
| `bridge-webview-windows` skill | executeScript, Dart/page messaging, bootstrap scripts, local/bundled content, cookies around login flows | JSON asymmetry rules, virtual-host + `flutter_assets` recipe, security notes |
| `troubleshoot-webview-windows` skill | Blank views, init failures, focus/keyboard complaints, missing menus, silent streams, NuGet/CMake/VS build errors | Symptom-to-fix tables, complete native error-code catalog |
| `test-webview-windows` skill | Writing/fixing tests that touch WebviewController or Webview | Copyable channel fake (verified by `flutter test`), `runAsync` rules, event injection |
| `migrate-from-webview-windows` skill | Projects on upstream `webview_windows` 0.x, or "fix the focus loss issue" | Ordered 10-step migration, complete rename map, before/after example |
| Eval suite (`evals/`) | Maintainer-run behavior checks | Five scenario cases with grader rubrics (positive, negative, failure-handling) |

There are deliberately **no** hooks, MCP servers, custom agents, or
executable scripts: nothing runs automatically, nothing needs network
access, and nothing asks for extra permissions. Installing the plugin only
adds instructions that load when relevant.

Repo-local (not part of the installable plugin): `AGENTS.md` / `CLAUDE.md`
maintainer guidance and the maintainer skills in `.claude/skills/`
(mirrored to `.agents/skills/`) for adding controller methods and preparing
releases.

## Install

### Claude Code

Inside a Claude Code session (CLI or desktop app):

```text
/plugin marketplace add omar-hanafy/webview_flutter_windows
/plugin install webview-flutter-windows@webview-flutter-windows
```

Run `/reload-plugins` to activate immediately, or start a new session.
Non-interactive equivalents exist (`claude plugin marketplace add ...`,
`claude plugin install ...`).

### OpenAI Codex

From a terminal (Codex CLI; installed plugins also surface in the ChatGPT
desktop app's Codex/Work modes, but not in the IDE extension):

```sh
codex plugin marketplace add omar-hanafy/webview_flutter_windows
codex plugin add webview-flutter-windows@webview-flutter-windows
```

Start a **new** Codex session afterwards; plugins do not hot-load.

### Use

Skills activate automatically when a task matches their description.
Explicit invocation: `/webview-flutter-windows:<skill-name>` in Claude Code,
`$<skill-name>` in Codex (for example
`/webview-flutter-windows:migrate-from-webview-windows`).

Example prompts:

- "Add an embedded browser pane with an address bar to my Windows app."
- "Users report typing keeps going into the page; investigate."
- "Write widget tests for this screen; it owns a WebviewController."
- "Move this app off webview_windows to the maintained fork."

## Updating and uninstalling

Claude Code: `/plugin update webview-flutter-windows@webview-flutter-windows`,
`/plugin uninstall webview-flutter-windows@webview-flutter-windows`, and
`/plugin marketplace remove webview-flutter-windows` to drop the catalog.

Codex: `codex plugin marketplace upgrade webview-flutter-windows` refreshes
the catalog, `codex plugin remove webview-flutter-windows@webview-flutter-windows`
uninstalls, `codex plugin marketplace remove webview-flutter-windows` drops
the catalog.

## Compatibility

- Plugin version = the package version it was released with; skills document
  the 1.x API (`setDefaultContextMenusEnabled` requires package `>=1.1.0`).
- Claude Code: any current release with plugin support (validated against
  2.1.x).
- Codex: any current CLI with GA plugin support (validated against 0.144.x).
  Codex also reads Claude-format marketplaces, so older fallback paths keep
  working.
- The skills are plain Markdown following the open Agent Skills format, so
  other agentskills-compatible tools can consume the `skills/` directory.

## Troubleshooting the plugin itself

| Symptom | Fix |
| --- | --- |
| `marketplace add` cannot find a catalog | Use exactly `omar-hanafy/webview_flutter_windows` (both tools accept `owner/repo`); check network access to GitHub |
| Skills do not appear after install | Claude Code: `/reload-plugins` or new session. Codex: a new session is required |
| Skill triggers on the wrong platform work | The skills self-limit to Windows tasks; if one misfires, invoke the right one explicitly and report an issue |
| Installed but outdated content | Update commands above; the plugin updates with package releases |

## For maintainers

Everything lives under `agent_plugins/webview-flutter-windows/`:

- One directory per skill: `skills/<name>/SKILL.md` with frontmatter exactly
  `name` (kebab-case, equal to the directory name) and `description`
  (trigger conditions only, max 1024 chars); heavy material goes in
  `references/` inside the skill.
- Both manifests (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`)
  and the repo marketplaces (`.claude-plugin/marketplace.json`,
  `.agents/plugins/marketplace.json`) must carry the package version.
- Validate locally: `dart tool/validate_agent_plugin.dart` (also a CI job),
  plus `claude plugin validate . --strict` in the repo root and the plugin
  directory when the Claude CLI is available.
- Smoke-test behavior: `claude --plugin-dir agent_plugins/webview-flutter-windows`
  and run the prompts from `evals/*/prompt.md`, scoring against
  `evals/*/graders/rubric.md`; for Codex, `codex plugin marketplace add
  <repo-checkout-path>` then `codex plugin add ...` and run the same
  prompts.
- Release flow (version sync, changelog, tag automation):
  `.claude/skills/prepare-release/SKILL.md`.
- **Standing rule**: every future release with a nontrivial breaking change
  must add a dedicated versioned migration skill
  (`migrate-v1-to-v2` style) next to `migrate-from-webview-windows`, plus an
  eval case with a fixture in the old API.

# webview_flutter_windows - agent guide

Flutter plugin embedding WebView2 as a texture on Windows. Maintained fork
of jnschulze/flutter-webview-windows; published on pub.dev as
`webview_flutter_windows`. Dart API in `lib/`, native C++ in `windows/`.

## Validation commands

Every code change:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Example changes: also `cd example && flutter analyze && flutter test`.
Native (`windows/`) changes, on a Windows host: `cmake -S windows/test -B
build/native_tests && cmake --build build/native_tests --config Release &&
ctest --test-dir build/native_tests -C Release --output-on-failure`, plus
`cd example && flutter build windows --release`. On non-Windows hosts state
that these gates are deferred to CI; never claim them run.
Agent-plugin or marketplace changes: `dart tool/validate_agent_plugin.dart`.

## Hard rules

- Three-layer contract: a controller method exists in `lib/src/webview.dart`
  (Dart + dartdoc), `windows/webview_bridge.cc` (channel constant +
  validation), and `windows/webview.h/.cc` (implementation), with a test in
  `test/webview_flutter_windows_test.dart`. Change all layers together;
  follow `.claude/skills/add-controller-method/SKILL.md`.
- Enum order is the wire format shared with C++ (`windows/webview.h`,
  `COREWEBVIEW2_*`). Append only; never reorder; update the "native enum
  contracts" test group.
- Do not bump `pubspec.yaml` version or edit `CHANGELOG.md` in normal PRs.
  Releases are version-bump PRs (see `.claude/skills/prepare-release/SKILL.md`);
  merged to `main` (stable) or `dev` (prerelease), automation creates the
  `webview_flutter_windows-v<version>` tag and publishes. Never tag or
  `dart pub publish` manually; never move an existing tag.
- Preserve the focus invariant (while a Flutter text input owns Flutter
  focus, no webview keeps native keyboard focus). Its tests live in the
  "Webview widget" group and `example/integration_test/focus_test.dart`.
- Public API needs dartdoc (`public_member_api_docs` is an error) and
  backward compatibility; breaking changes require prior agreement.
- All controller event streams are broadcast; new streams must be too, and
  must be closed in `dispose()`.
- Keep `.claude/skills/` and `.agents/skills/` byte-identical (the
  validator checks); consumer-facing skills live only under
  `agent_plugins/webview-flutter-windows/`.
- The pub.dev archive must not ship agent tooling: `.pubignore` excludes
  `agent_plugins/`, `.claude/`, `.agents/`, `AGENTS.md`, `CLAUDE.md`,
  `tool/`, `docs/`. Keep it that way.

## Pointers

- Contributor standards: `.github/CONTRIBUTING.md`
- Upgrade guide (upstream 0.4.x -> 1.x): `migration_guide.md`
- Consumer agent plugin (skills, evals): `agent_plugins/webview-flutter-windows/`
- Maintainer skills: `.claude/skills/` (mirrored in `.agents/skills/`)

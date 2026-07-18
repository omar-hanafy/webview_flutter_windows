# Contributing to webview_flutter_windows

Thanks for helping improve `webview_flutter_windows`. Contributions of code,
tests, documentation, bug reports, examples, and design feedback are welcome.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md) in every project space.
For usage help, see [Support](SUPPORT.md). Report security vulnerabilities using
the private process in [Security](SECURITY.md), never a public issue.

## Choose the right starting point

- Use the [bug report form](https://github.com/omar-hanafy/webview_flutter_windows/issues/new?template=bug_report.yml)
  for reproducible defects.
- Use the [feature request form](https://github.com/omar-hanafy/webview_flutter_windows/issues/new?template=feature_request.yml)
  for new behavior or public API proposals.
- Use the [documentation form](https://github.com/omar-hanafy/webview_flutter_windows/issues/new?template=documentation.yml)
  for unclear, missing, or incorrect documentation.
- Use the [question form](https://github.com/omar-hanafy/webview_flutter_windows/issues/new?template=question.yml)
  when the README, troubleshooting section, and existing issues do not answer a
  usage question.

Search open and closed issues before filing a new one. Small, well-understood
fixes can go directly to a pull request. Please open an issue before investing
in a breaking change, a new public API, a large native rewrite, or a change to
default behavior so the design can be agreed first.

## Development setup

The package requires Flutter 3.44 or newer and Dart 3.12 or newer. Dart-only
and documentation changes can be prepared on any platform. Native development
and the runnable example require:

- Windows 10 or 11
- Visual Studio 2022 with the Desktop development with C++ workload
- a Windows 10 or 11 SDK
- the Microsoft Edge WebView2 Runtime

Fork the repository, clone your fork, and branch from the latest `main`:

```sh
git clone https://github.com/YOUR_ACCOUNT/webview_flutter_windows.git
cd webview_flutter_windows
git remote add upstream https://github.com/omar-hanafy/webview_flutter_windows.git
git fetch upstream
git switch -c your-change upstream/main
dart pub get
```

Ordinary contributions target `main`. The `dev` branch is reserved for the
maintainer's prerelease lane.

## Design and implementation standards

- Keep public Dart APIs typed, documented, and backward compatible unless a
  breaking change has been agreed in advance.
- Preserve existing defaults when adding opt-in behavior.
- Keep Dart, method-channel, and native method names and argument contracts in
  sync.
- Validate method-channel arguments and return structured errors instead of
  crashing or silently failing.
- Treat COM ownership and `HRESULT` handling explicitly. Use the existing RAII
  conventions and test both success and failure paths.
- Add focused tests for observable behavior, lifecycle boundaries, invalid
  input, and platform-error propagation.
- Update the README, example, and Dartdoc when users need new setup or usage
  guidance.
- Keep pull requests focused. Avoid unrelated formatting or refactoring.

Maintainers may add follow-up commits to a contributor branch when permitted,
or propose an alternative implementation to preserve API and native-layer
consistency. The pull request and original commits remain attributed to the
contributor.

## Validation

Run the checks that apply to your change and list anything you could not run in
the pull request.

For every code change:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

If the example changes:

```sh
cd example
flutter pub get
flutter analyze
flutter test
```

For native Windows changes, also run from the repository root:

```sh
cmake -S windows/test -B build/native_tests
cmake --build build/native_tests --config Release
ctest --test-dir build/native_tests -C Release --output-on-failure
cd example
flutter build windows --release
```

Input and focus changes should also exercise
`example/integration_test/focus_test.dart` in an interactive Windows session.
If Windows is unavailable for a Dart-only or documentation contribution, say
so in the pull request and let CI run the Windows gates.

Release-only checks are run by maintainers:

```sh
dart pub publish --dry-run
dart pub global activate pana 0.23.14
pana --exit-code-threshold 0 .
```

## Pull requests

- Link the issue or explain why one is unnecessary.
- Explain the user-visible behavior, compatibility impact, and design choices.
- Include tests for code changes and screenshots or logs when they clarify the
  result.
- Complete the pull request template honestly, including the checks not run.
- Keep commits reviewable and preserve your own authorship information.
- By contributing, you agree that your contribution is licensed under the
  repository's [BSD 3-Clause License](../LICENSE).

Do not change `pubspec.yaml` version or `CHANGELOG.md` in a normal contribution.
Maintainers prepare release versions and changelogs from the final public delta
after contributions are merged.

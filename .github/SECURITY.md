# Security policy

## Supported versions

Security fixes are provided for the latest stable pub.dev release. Please
confirm the issue still affects that version before reporting it.

| Version | Supported |
| --- | --- |
| Latest stable release | Yes |
| Older releases and prereleases | No |

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/omar-hanafy/webview_flutter_windows/security/advisories/new)
so details remain private while the report is investigated.

Include as much of the following as you safely can:

- affected package and WebView2 Runtime versions
- Windows and Flutter versions
- impact and realistic attack scenario
- minimal reproduction steps or a private proof of concept
- affected APIs or native code paths
- suggested mitigation, if known

Never include real credentials, cookies, tokens, private URLs, or personal
data. Use synthetic test values and redact logs.

Reports involving the native bridge, browser profile or cookies, JavaScript
messages, content loading, input forwarding, or WebView2 integration are in
scope when package behavior contributes to the issue. Vulnerabilities entirely
inside Microsoft Edge WebView2 should also be reported to Microsoft.

The maintainer will acknowledge the report, assess its scope and severity, and
coordinate a fix and disclosure when appropriate. Please avoid public
disclosure until a fix is available or a disclosure timeline has been agreed.
Reporter credit is welcomed unless anonymity is requested.

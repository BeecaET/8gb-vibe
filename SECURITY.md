# Security policy

English | [Tiếng Việt](#chính-sách-bảo-mật)

## Supported versions

Only the latest release of 8GB Vibe gets security fixes. Download it at https://8gb.beeca.vn.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Older releases | No, please update |
| Builds from a fork or a local build | No |

## Reporting a vulnerability

Please do **not** open a public issue for a security problem.

Report it privately through GitHub: open the **Security** tab of this repository, then **Report a vulnerability** ([GitHub private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)). Only the maintainers can see the report.

Please include:

- The 8GB Vibe version and build (About page), macOS version, Mac model and RAM.
- What an attacker can do, and the steps to reproduce it.
- Whether you plan to publish, and when.

We will reply as soon as we can, keep you informed while we work on a fix, and credit you in the release notes if you want.

## Scope

In scope, for example:

- The app quitting, stopping or deleting something without the user's confirmation, or a process that is on the never-quit list.
- Data leaving the Mac. The app is meant to send nothing anywhere.
- Files written by the app (log, measurements) readable by other users, or paths that can be redirected.
- Problems in the signed and notarized release build.

Out of scope:

- Reports that need an attacker who already runs code as your user or as root.
- Builds that are not signed by BEECA.
- Issues in macOS itself (please report those to Apple).

---

## Chính sách bảo mật

Chỉ bản phát hành mới nhất được vá lỗi bảo mật. Vui lòng **không** mở issue công khai cho lỗi bảo mật. Báo riêng qua GitHub: tab **Security** của repo, chọn **Report a vulnerability**. Ghi rõ phiên bản, macOS, máy, RAM, cách tái hiện và tác động. Phạm vi gồm: app tự tắt hay xoá mà không hỏi, dữ liệu rời khỏi máy, tệp của app để lộ cho người dùng khác, lỗi ở bản phát hành đã ký.

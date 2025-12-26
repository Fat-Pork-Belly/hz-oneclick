# Environment variables

This page lists the environment variables referenced by the scripts in this repo.
Defaults are shown when the script provides one. All examples use placeholders.

## Supported variables

### Runtime/configuration variables

| Name | Required? | Default | Purpose | Where used (file/module) | Example value |
| --- | --- | --- | --- | --- | --- |
| `HZ_LANG` | No | Empty (menu prompt) | Preselect UI language for `hz.sh` and baseline wrappers. | `hz.sh`, `modules/diagnostics/baseline-wrapper-common.sh` | `en` |
| `HZ_BASELINE_LANG` | No | `zh` (or `HZ_LANG`) | Default language for baseline wrappers. | `modules/diagnostics/baseline-wrapper-common.sh` | `en` |
| `HZ_BASELINE_FORMAT` | No | `text` | Default output format for baseline wrappers. | `hz.sh`, `modules/diagnostics/baseline-wrapper-common.sh` | `json` |
| `HZ_BASELINE_DOMAIN` | No | Empty | Default domain passed to baseline wrappers. | `modules/diagnostics/baseline-wrapper-common.sh` | `abc.yourdomain.com` |
| `HZ_BASELINE_REDACT` | No | `0` | Enable redaction by default for baseline wrappers. | `modules/diagnostics/baseline-wrapper-common.sh` | `1` |
| `BASELINE_REDACT` | No | `0` (or `HZ_BASELINE_REDACT`) | Redact sensitive tokens in baseline output. | `modules/diagnostics/baseline-wrapper-common.sh`, `lib/baseline_common.sh`, `modules/diagnostics/quick-triage.sh` | `1` |
| `HZ_INSTALL_BASE_URL` | No | Script default URL | Base URL for installer assets. | `hz.sh`, `modules/security/install-rkhunter*.sh`, `modules/diagnostics/quick-triage.sh` | `https://example.invalid/hz-oneclick` |
| `HZ_TRIAGE_RAW_BASE` | No | `HZ_INSTALL_BASE_URL` | Base URL for quick triage library downloads. | `modules/diagnostics/quick-triage.sh` | `https://example.invalid/hz-oneclick` |
| `HZ_TRIAGE_KEEP_TMP` | No | `0` | Keep the quick triage temp directory. | `modules/diagnostics/quick-triage.sh` | `1` |
| `HZ_TRIAGE_USE_LOCAL` | No | `0` | Read quick triage libs from local repo instead of downloading. | `modules/diagnostics/quick-triage.sh` | `1` |
| `HZ_TRIAGE_LOCAL_ROOT` | No | `pwd` | Local repo root when `HZ_TRIAGE_USE_LOCAL=1`. | `modules/diagnostics/quick-triage.sh` | `/opt/hz-oneclick` |
| `HZ_TRIAGE_REDACT` | No | `0` | Redact quick triage output. | `modules/diagnostics/quick-triage.sh` | `1` |
| `HZ_TRIAGE_TEST_MODE` | No | `0` | Enable quick triage test mode (non-interactive defaults). | `modules/diagnostics/quick-triage.sh` | `1` |
| `HZ_TRIAGE_LANG` | No | `zh` | Default prompt language for quick triage. | `modules/diagnostics/quick-triage.sh` | `en` |
| `HZ_TRIAGE_DOMAIN` | No | Empty | Default domain prompt value for quick triage. | `modules/diagnostics/quick-triage.sh` | `abc.yourdomain.com` |
| `HZ_TRIAGE_TEST_DOMAIN` | No | `abc.yourdomain.com` | Default domain in triage test mode. | `modules/diagnostics/quick-triage.sh` | `abc.yourdomain.com` |
| `HZ_CI_SMOKE` | No | `0` | Enable smoke-mode triage behavior (truthy values). | `modules/diagnostics/quick-triage.sh`, `lib/baseline_triage.sh` | `1` |
| `HZ_SMOKE_STRICT` | No | `0` | Treat WARN as failure in smoke mode (truthy values). | `lib/baseline_triage.sh`, `tests/smoke.sh` | `1` |
| `BASELINE_TEST_MODE` | No | `0` | Enable baseline test mocks (used by triage and tests). | `modules/diagnostics/quick-triage.sh`, `lib/baseline_triage.sh` | `1` |
| `BASELINE_WP_NO_PROMPT` | No | Empty | Skip WP prompts during baseline runs. | `modules/diagnostics/quick-triage.sh`, `lib/baseline_wp.sh` | `1` |
| `BASELINE_LAST_REPORT_PATH` | No | Empty | Populated with the last baseline report path. | `lib/baseline_triage.sh`, `modules/diagnostics/quick-triage.sh` | `/tmp/hz-baseline-triage-abc.yourdomain.com-20240101-120000.txt` |
| `BASELINE_LAST_REPORT_JSON_PATH` | No | Empty | Populated with the last baseline JSON report path. | `lib/baseline_triage.sh`, `tests/smoke.sh` | `/tmp/hz-baseline-triage-abc.yourdomain.com-20240101-120000.json` |
| `LANG` | No | System default | Locale used by WP install script. | `modules/wp` (standard WP installer script) | `en_US.UTF-8` |

### Test-only helpers

| Name | Required? | Default | Purpose | Where used (file/module) | Example value |
| --- | --- | --- | --- | --- | --- |
| `HZ_SMOKE_SELFTEST` | No | Empty | Run smoke self-test assertions. | `tests/smoke.sh` | `1` |
| `BASELINE_SMOKE_STEP_TIMEOUT` | No | `10s` | Timeout per smoke test step. | `tests/baseline_smoke.sh` | `30s` |

## How to set them safely

- **Shell session**: export before running a script.
  ```bash
  export HZ_BASELINE_FORMAT=json
  export HZ_TRIAGE_USE_LOCAL=1
  ```
- **Local env file**: keep a private file and source it in your shell.
  ```bash
  printf '%s\n' "HZ_TRIAGE_DOMAIN=abc.yourdomain.com" > ./local.env
  set -a
  . ./local.env
  set +a
  ```
- **CI secrets**: add them as masked variables in your CI system, then pass
  them to the job environment.

## Security notes

- Never commit secrets to the repository.
- Use placeholders in docs and examples (like `abc.yourdomain.com` or
  `<YOUR_TOKEN>`).
- Prefer scoped credentials and rotate them regularly.

## Quoting notes

If a value includes spaces or special characters, wrap it in single quotes:

```bash
export HZ_TRIAGE_DOMAIN='abc.yourdomain.com'
```

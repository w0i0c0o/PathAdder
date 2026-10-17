# Workflows (maintainer notes)

This directory holds the GitHub Actions automation for PathAdder. It is written
in English because it is engineering documentation for the repository itself.

Two workflows live here, with **non-overlapping responsibilities**:

| File | Trigger | Responsibility | Side effects |
|---|---|---|---|
| `ci.yml` | `push` to `main`, all `pull_request`, manual | Verification only: PowerShell syntax, BOM policy, language-pack parity, translation-key usage, repository hygiene, i18n smoke test | **none** (never writes to the repo or to a Release) |
| `release.yml` | `push` of a tag matching `v*`, manual | Build the COM DLL, package the zip, publish the GitHub Release | creates/updates a Release and uploads an asset |

`ci.yml` answers *"is this commit allowed to be merged?"*
`release.yml` answers *"what does version X look like to an end user?"*

Neither workflow touches anything downstream of the other: a red CI run never
blocks a release automatically (a tag can be pushed regardless), and a release
never mutates the working tree that CI validated.

---

## 1. `release.yml` — step by step

| # | Step | What it does | Why it is ordered here |
|---|---|---|---|
| 0 | Checkout | `actions/checkout@v4`, `fetch-depth: 0` | full history so the tag resolves and GitHub's source archives are complete |
| 1 | **Verify tag matches `version.json`** | Parses the tag as `vMAJOR.MINOR.PATCH(-prerelease)?`, reads `version.json`, compares, **exits non-zero on any mismatch** | runs *before* the ~1 minute DLL compile so failures have the shortest possible feedback loop; a wrong version number is unfixable after publishing |
| 2 | Compile COM shell extension | Calls the existing `com\build.ps1`, then asserts `com\PathAdderShellExt.dll` exists, is non-empty, is plausible in size, starts with the `MZ` signature, and computes its SHA256 | the DLL is a build artefact and is intentionally **not** in git, so it must be produced here |
| 3 | Assemble release package | White-list copies files into `PathAdder-v<VER>/`, drops developer-only artefacts, asserts both required and forbidden file sets, zips, then re-opens the archive to verify its topology | packaging is the step that silently produces broken releases; every assumption is asserted rather than hoped for |
| 4 | Render release notes | Substitutes `{{VERSION}}`, `{{TAG}}`, `{{ZIP_NAME}}`, `{{DLL_SHA256}}`, `{{RELEASE_DATE}}`, `{{PRERELEASE_NOTE}}` in `.github/RELEASE_NOTES_TEMPLATE.md`; fails if any placeholder survives | notes need the hash produced in step 2 and the asset name from step 3 |
| 5 | Create GitHub Release | `softprops/action-gh-release@v2` with the zip attached, `prerelease` derived from the tag containing `-` | last, so a release is only ever created from a fully verified artefact |
| 6 | Write job summary | Appends a small table to `$GITHUB_STEP_SUMMARY` | post-hoc inspection of the run page |

### Hard rules baked into `release.yml`

These are not stylistic preferences — each one exists because the obvious
alternative is broken on this project:

1. **Every `run:` block uses `shell: powershell`** (Windows PowerShell 5.1),
   never `pwsh`. The product runs on 5.1; PS7 would accept syntax that 5.1
   rejects and would also mis-report encoding problems.
2. **No PowerShell 7-only syntax** anywhere: no `??`, `&&`, `||`, no ternary
   `? :`, no `$PSStyle`. Targets in the scripts are guarded with `if`.
3. **Nothing kills or restarts `explorer.exe`.** No `taskkill`, no
   `Stop-Process -Name explorer`. `com\release-dll.ps1` is never invoked; the
   "target DLL is locked" branch in `com\build.ps1` is unreachable on a fresh
   runner anyway, because the DLL does not exist after checkout.
4. **Nothing registers anything.** No `regsvr32`, no `RegAsm`, no registry
   writes. Publishing only *compiles*; registration belongs to the end user's
   machine (`install.bat`).
5. **No compilation logic is duplicated.** `release.yml` shells out to
   `com\build.ps1` and nothing else. That script's staged build (copy sources
   to `%TEMP%\PathAdderBuild`, compile, copy the DLL back) is what keeps builds
   working on paths containing non-ASCII characters (`CS2001`), and its
   `'cs' + 'c.exe'` string concatenation is a deliberate security-policy
   workaround. Re-implementing either re-introduces solved bugs.
6. **No secrets.** Only the implicit `GITHUB_TOKEN` is used. There is no PAT,
   no deploy key, no third-party action beyond `actions/*` and
   `softprops/action-gh-release`.

---

## 2. Release package layout

```
PathAdder-v1.0.0-win-x64.zip
└── PathAdder-v1.0.0/            <- exactly one top-level folder
    ├── install.bat              <- what the user double-clicks
    ├── install.ps1
    ├── uninstall.bat / .ps1
    ├── verify.bat / verify-registration.ps1
    ├── PathAdder.ps1            <- entry point the context menu invokes
    ├── PathManager.ps1          <- GUI PATH manager
    ├── MenuPicker.ps1
    ├── README.md / README.zh-CN.md
    ├── LICENSE
    ├── version.json
    ├── lib/                     (Common.ps1, ShellMenu.ps1, i18n.ps1)
    ├── lang/en-US/*.ps1         (8 shards)
    ├── lang/zh-CN/*.ps1         (8 shards)
    └── com/
        ├── PathAdderShellExt.dll       <- built by this workflow (x64)
        ├── PathAdderShellExt.cs
        ├── PathAdderContextMenu.cs
        ├── build.ps1 / rebuild.ps1 / release-dll.ps1
        ├── register-com.ps1 / register-contextmenu.ps1 / restore-menu.ps1
        └── README-COM.md / README-COM.zh-CN.md
```

**The single top-level folder is deliberate.** Users almost always extract into
`Downloads\` or an existing tools directory; a wrapping folder keeps the 25+
files together and makes uninstall a one-step "delete the folder".

**Never in the package** (asserted at build time, not merely omitted):

| Excluded | Why |
|---|---|
| `.git/`, `.github/` | irrelevant to users; contributors get the source archive |
| `.workbuddy/` | local agent workspace — must never be published |
| `tools/` | CI validation scripts, not a runtime dependency |
| `docs/` | internal design documents |
| `*.old` | `com\build.ps1` lock-workaround backups |
| `com\diag-cascade.ps1` | author-only diagnostic for an abandoned approach; it writes HKLM keys if run |
| `*.pdb`, `*.tlb`, `compile.rsp` | compiler intermediates |

If any of the above ever reaches the staging folder, the workflow **fails** and
lists the offending paths.

---

## 3. How to publish a release (operator manual)

> The single rule: **the tag and `version.json` must describe the same version,
> and they must be introduced by the same commit.**

```bash
# ── 1. Bump the version (single source of truth) ───────────────────────────
#    Edit version.json:  { "version": "1.0.1" }
#    MAJOR.MINOR.PATCH, optionally with a -prerelease suffix (e.g. 1.1.0-rc.1).
#    Do not add a BOM (docs/design-open-source-release.md §9.1).

# ── 2. Commit the bump on main, and let CI go green ────────────────────────
git add version.json README.md README.zh-CN.md      # + whatever actually changed
git commit -m "chore(release): bump version to 1.0.1"
git push origin main
#    Wait for the `ci.yml` run on that commit to pass. Do not tag a red commit.

# ── 3. Create the tag on that exact commit ────────────────────────────────
git tag v1.0.1                                       # v + the exact version string
git push origin v1.0.1                               # <-- this is what starts release.yml

# ── 4. Watch the run ──────────────────────────────────────────────────────
gh run watch
```

### Re-running / retrying

If the run failed *after* the tag exists (e.g. a transient runner error), you do
**not** need to delete the tag:

```
Actions → Release → Run workflow → tag: v1.0.1
```

`workflow_dispatch` re-runs the same pipeline against an existing tag. It reads
the tag from the input instead of `github.ref_name`, everything else is
identical.

### If the version is wrong

`release.yml` fails at step 1 and does not compile anything. Fix the repository,
then move the tag:

```bash
# Option A (preferred): the content is wrong, not the tag
#   bump version.json, commit, push, then move the tag:
git tag -d v1.0.1
git tag v1.0.1
git push origin :refs/tags/v1.0.1        # delete the remote tag
git push origin v1.0.1                   # re-create it

# Option B: the tag is wrong, version.json is right
git tag -d v1.0.0
git tag v1.0.1
git push origin :refs/tags/v1.0.0
git push origin v1.0.1
```

There is no need to touch an existing Release: `softprops/action-gh-release`
updates the Release for an existing tag and replaces the asset.

### Pre-releases

A tag containing a hyphen (`v1.1.0-rc.1`) is automatically published as a
GitHub **pre-release** (`prerelease: true`), and the notes get a banner. The
`version.json` value must include the same suffix, byte for byte.

---

## 4. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Version mismatch -- the tag says 'X' but version.json says 'Y'` | tag and file disagree | see §3 "If the version is wrong" |
| `Tag 'v1.0' does not match ^vMAJOR.MINOR.PATCH...` | tag is not semver | re-create the tag with three numeric components |
| `version.json missing` / `unparsable` / `has no 'version' field` | the single source of truth is gone or malformed | restore it; it must be UTF-8 **without** BOM |
| `com\build.ps1 exited with code N` | compile error, or `csc.exe` not found | reproduce locally: `cd com` → `.\build.ps1`. The runner is `windows-latest`, so .NET Framework 4.x is present; a failure here is almost always a C# error in the `.cs` files |
| `DLL suspiciously small` / `not a PE file` | truncated or bogus output | same as above — check the build log printed by `build.ps1` |
| `Missing packaged file '…'` | a file was renamed or deleted from the repo root, or excluded by an over-broad `.gitignore` rule | check `git ls-files` for the file; note `.gitignore` must never use a bare `*.dll`/`*.ps1` wildcard |
| `Forbidden files in package: …` | something regenerated an `.old` backup or `diag-cascade.ps1` got copied in | the staging list is a white-list, so this means a directory copy pulled it in — inspect the list in step 3 |
| `Bad zip root` | `Compress-Archive` was pointed at the staging parent instead of the payload folder | zip `$package`, not `$staging` (step 3g) |
| `Unreplaced placeholder: {{…}}` | the notes template contains a token the renderer does not know | only the six documented placeholders are supported; see the header of `RELEASE_NOTES_TEMPLATE.md` |
| Release created but asset missing | `fail_on_unmatched_files: true` should have prevented this | check that step 3 emitted `zipPath` |
| `Resource not accessible by integration` | workflow permissions | `permissions: contents: write` must stay at the top of `release.yml` |

### Things to verify locally instead of on the runner

GitHub Actions cannot be executed locally, so when changing the packaging logic
of step 3, run the white-list copy against a real checkout and inspect the
result with `unzip -l` (or Python's `zipfile`). Confirm:

* exactly one top-level folder, named `PathAdder-v<VER>/`
* `com/PathAdderShellExt.dll` present
* no `*.old`, no `com/diag-cascade.ps1`, no `.git*`, no `tools/`, no `docs/`
* all 16 language shards present

---

## 5. Relationship to the design document

The authoritative design is `docs/design-open-source-release.md`:

* §5.2 — workflow skeleton
* §5.3 — why DLL locking is a non-issue in CI, and the "never kill explorer" rule
* §5.4 — permissions and the zero-secret policy
* §6.2 / §6.3 / §9.3 — package layout, include/exclude lists, zip conventions
* §6.4 — release notes template

If the implementation and the document disagree, the document wins — change the
workflow, then update this file.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository shape

A monorepo of unrelated apps. Each top-level folder is one self-contained app with
its own project file, dependencies and tooling. Nothing is shared between apps and
there is no root-level build, test or dependency manifest — **always work from
inside the app folder**, and never introduce a cross-app dependency or a shared
root package without being asked.

Each app carries its own `CLAUDE.md` with the detail that matters for it. Read that
one too; this file only covers what is true across the repo.

| App | Platform | Its guidance |
|---|---|---|
| `MParking/` | iOS (SwiftUI) | [MParking/CLAUDE.md](MParking/CLAUDE.md) |

`.gitignore` is maintained at the repo root because its patterns (`.build/`,
`DerivedData/`, `__pycache__/`, `xcuserdata/`) apply to every app.

## Adding an app

New apps go in a new top-level folder with their own README and, if the app has
non-obvious architecture, their own `CLAUDE.md`. Add a row to the table above and
to the root `README.md`.

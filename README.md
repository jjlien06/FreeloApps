# FreeloApps

Apps I build. Each one is a self-contained folder — its own project file,
dependencies, tooling and README — so nothing here is shared between them and
adding a new app never means touching an existing one.

| App | Platform | What it does |
|---|---|---|
| [MParking](MParking/) | iOS | Finds parking that is free right now at U-M Ann Arbor, based on each lot's posted enforcement hours |
| [Heft](Heft/) | iOS | Sorts your photo library by file size — the thing Photos.app won't do — then exports to an external drive or converts RAW, before deleting |
| [SnipText](SnipText/) | macOS | Menu-bar OCR: hotkey → drag a box around any on-screen text → it lands on your clipboard, all on-device via Apple Vision |

## Building and running

There is no root build — every app builds from inside its own folder, and each
README covers its app in depth (usage, architecture, data sources, caveats).

| App | Build & run | Tests |
|---|---|---|
| MParking | open `MParking/MParking.xcodeproj`, ⌘R to a simulator or your iPhone | `cd MParking/Packages/ParkingKit && swift test` |
| Heft | open `Heft/Heft.xcodeproj`, ⌘R — needs a real photo library to be interesting | in-app debug smoke test (see its README) |
| SnipText | `cd SnipText && make run` — builds, signs, installs to `~/Applications`, launches | `cd SnipText && make test` |

The iOS apps are personal builds: install through Xcode with your own Apple ID.
On a free account a device holds at most 3 sideloaded apps and each install
expires after 7 days — rebuild to renew. MParking regenerates its project with
`xcodegen generate` when source files are added or removed (`project.yml` is the
source of truth). SnipText signs with your Apple Development certificate so its
Screen Recording permission survives rebuilds.

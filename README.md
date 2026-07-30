# FreeloApps

Apps I build. Each one is a self-contained folder — its own project file,
dependencies, tooling and README — so nothing here is shared between them and
adding a new app never means touching an existing one.

| App | Platform | What it does |
|---|---|---|
| [MParking](MParking/) | iOS | Finds parking that is free right now at U-M Ann Arbor, based on each lot's posted enforcement hours |
| [Heft](Heft/) | iOS | Sorts your photo library by file size — the thing Photos.app won't do — then exports to an external drive or converts RAW, before deleting |

## Working in a single app

Everything is scoped to the app folder. There is no root build.

```sh
cd MParking
cat README.md
```

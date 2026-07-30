# Release 1.2 - Default Affair Name Sort

**Release date:** 2026-07-30  
**Module id:** `org.openconcerto.modules.project`  
**Module version:** `1.2`  
**Primary artifact:** `org.openconcerto.modules.project-1.2.jar`

## Executive Summary

Release `1.2` changes the default sorting behavior of the history screen's affair selector.
When the user opens `Historique affaires`, the affair list now starts in `Tri par nom` mode instead of `Tri par date`.

The change is intentionally narrow: it modifies the initial UI state and the initial comparator only.
The existing date sort remains available from the same combo box, and the closed-affair filter remains active by default.

## Business Requirement

The module previously presented affairs by date by default. Johan requested that the default displayed sort be by name.

Expected behavior:

- Opening the history screen displays the sort selector on `Tri par nom`.
- The affairs are initially ordered by the existing name comparator.
- Users can still switch to `Tri par date`.
- The `Masquer dossiers clos` checkbox remains selected by default.

## Implementation Details

Updated file:

- `src/org/openconcerto/modules/project/ProjectHistory.java`

Changed behavior:

- `installHistoryControls()` now installs the affair-list sort with `sortByDate = false`.
- `installProjectListControls()` now initializes the sort combo with index `1`, corresponding to `Tri par nom`.

The implementation reuses the existing comparator code:

- Name comparator: `createAffairNameComparator(...)`
- Date comparator: `createAffairDateComparator(...)`
- Shared preload data: `loadAffairSortValues(...)`

No database schema change is required.

## Compatibility

- Java target: Java 8 bytecode.
- Host runtime: OpenConcerto runtime compatible with the current module API usage.
- Database: no migration required.
- Existing user workflow: compatible. The sort mode can still be changed manually from the UI.

## Build And Packaging

The release build is produced with:

```sh
./scripts/build-java8-compatible.sh
```

The build script now reads the module version from `module.properties` and emits:

```text
build/org.openconcerto.modules.project-1.2.jar
```

The generated JAR includes:

- compiled module classes;
- XML and properties resources from `src`;
- `META-INF/openConcertoModule.properties` copied from `module.properties`.

## Validation Checklist

Automated validation:

- Module compilation completed through `scripts/build-java8-compatible.sh`.
- Bytecode verification passed: all classes are major version `52` or lower.

Manual validation to perform in OpenConcerto:

1. Restart OpenConcerto.
2. Open `Historique des affaires`.
3. Confirm that the left-side affair sort selector displays `Tri par nom`.
4. Confirm that affairs are ordered by name on first display.
5. Switch to `Tri par date` and verify that date sorting still works.
6. Confirm that `Masquer dossiers clos` remains selected.

## Deployment Notes

Installed release path:

```text
/home/jojokes/.local/share/OpenConcerto/Modules/org.openconcerto.modules.project-1.2.jar
```

Operational steps:

1. Stop OpenConcerto before replacing module JARs when possible.
2. Keep one active JAR for `org.openconcerto.modules.project` in the modules directory.
3. Start OpenConcerto.
4. If the previous behavior is still visible, disable and re-enable the module in OpenConcerto module management, then restart.

## Rollback

Rollback consists of restoring the previous active module JAR and restarting OpenConcerto.

Previous known release:

```text
org.openconcerto.modules.project-1.1.jar
```

No database rollback is required for this release because no schema or data migration is included.

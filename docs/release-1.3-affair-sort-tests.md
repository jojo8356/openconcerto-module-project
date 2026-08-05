# Release 1.3 - Affair Sort Test Coverage

**Release date:** 2026-08-05  
**Module id:** `org.openconcerto.modules.project`  
**Module version:** `1.3`  
**Primary artifact:** `org.openconcerto.modules.project-1.3.jar`

## Executive Summary

Release `1.3` adds automated coverage for the affair history selector sorting rules.
The default remains `Tri par nom`, and the tests now protect that default from drifting away from the initially installed comparator.

## Implementation Details

Updated files:

- `src/org/openconcerto/modules/project/ProjectHistory.java`
- `src/org/openconcerto/modules/project/AffairListSortSupport.java`
- `tests/org/openconcerto/modules/project/AffairListSortSupportTest.java`
- `scripts/run-tests.sh`

Covered behavior:

- `Tri par nom` is the default combo selection.
- The initially applied default comparator is the name comparator.
- `Tri par date` orders dated affairs by most recent date first.
- Affairs without dates are placed after dated affairs.
- The undefined affair entry is handled consistently.
- Equal dates fall back to affair number ordering.
- Sort labels are built from affair number, client name, and affair name.

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

The automated sort tests are run with:

```sh
sh scripts/run-tests.sh
```

The build script reads the module version from `module.properties` and emits:

```text
build/org.openconcerto.modules.project-1.3.jar
```

## Validation Checklist

Automated validation:

- Sort tests pass through `scripts/run-tests.sh`.
- Module compilation completes through `scripts/build-java8-compatible.sh`.
- Bytecode verification passes: all classes are major version `52` or lower.

Manual validation to perform in OpenConcerto:

1. Restart OpenConcerto.
2. Open `Historique des affaires`.
3. Confirm that the left-side affair sort selector displays `Tri par nom`.
4. Confirm that affairs are ordered by name on first display.
5. Switch to `Tri par date` and verify that date sorting still works.
6. Confirm that `Masquer dossiers clos` remains selected.

## Rollback

Rollback consists of restoring the previous active module JAR and restarting OpenConcerto.

Previous known release:

```text
org.openconcerto.modules.project-1.2.jar
```

No database rollback is required for this release because no schema or data migration is included.

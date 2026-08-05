# Changelog

## 1.3 - 2026-08-05

### Added

- Automated tests for the affair history selector sort behavior.
- A lightweight `scripts/run-tests.sh` test runner for the extracted sort logic.

### Changed

- Extracted affair-list sort rules into a small testable support class.
- Centralized the default sort constants so the visible combo selection and the initially applied comparator stay aligned.

### Validation

- `sh scripts/run-tests.sh`
- `./scripts/build-java8-compatible.sh`
- Java bytecode verification: all classes are classfile major version `52` or lower.

### Artifact

- `build/org.openconcerto.modules.project-1.3.jar`

## 1.2 - 2026-07-30

### Added

- Professional release documentation for the default affair-name sort feature.

### Changed

- The history screen's affair selector now defaults to `Tri par nom`.
- The initial comparator installed on the affair selector now matches the visible default selection.
- The build script now derives the JAR version from `module.properties`, reducing release-version drift.

### Preserved

- Users can still switch manually to `Tri par date`.
- Closed affairs remain hidden by default through `Masquer dossiers clos`.
- Date rendering in the affair selector remains unchanged when affair dates are available.

### Validation

- `./scripts/build-java8-compatible.sh`
- Java bytecode verification: all classes are classfile major version `52` or lower.

### Artifact

- `build/org.openconcerto.modules.project-1.2.jar`
- `/home/jojokes/.local/share/OpenConcerto/Modules/org.openconcerto.modules.project-1.2.jar`

## 1.1 - 2026-07-08

### Changed

- Integrated the previous runtime patch behavior directly into source-controlled Java code.
- Added affair history sorting controls, closed-affair filtering, direct affair modification, optional-table tolerance, family filters, supplier display corrections, and Java 8 compatible packaging.

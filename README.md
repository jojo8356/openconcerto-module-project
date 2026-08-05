# OpenConcerto Project Module

Personal OpenConcerto module for project/affair management.

## Current Release

- Module id: `org.openconcerto.modules.project`
- Version: `1.3`
- Release date: `2026-08-05`
- Main change: the affair history selector default sort is now covered by automated tests.

The module has been compiled and installed locally as:

```text
/home/jojokes/.local/share/OpenConcerto/Modules/org.openconcerto.modules.project-1.3.jar
```

## Java Compatibility

The module is built for Java 8 bytecode so the same JAR can run on Java 8 through Java 21, provided the host OpenConcerto runtime is compatible.

Build the module with:

```sh
./scripts/build-java8-compatible.sh
```

The script uses `javac --release 8` on JDK 9+ and falls back to `-source 8 -target 8` on JDK 8. It then verifies that every compiled class in the JAR has classfile major version `52` or lower.

If OpenConcerto is not installed at `/opt/openconcerto/OpenConcerto.jar`, pass its path explicitly:

```sh
OPENCONCERTO_JAR=/path/to/OpenConcerto.jar ./scripts/build-java8-compatible.sh
```

## Notes

- Source code is under `src/org/openconcerto/modules/project`.
- Module metadata is in `module.properties`.
- The affair history list supports both `Tri par nom` and `Tri par date`; `Tri par nom` is the tested default release behavior.
- `DATE` remains available for date sorting and list display.
- Runtime bytecode/JAR patch classes have been removed.

## Documentation

- Release notes: `CHANGELOG.md`
- Technical release file: `docs/release-1.3-affair-sort-tests.md`
- Architecture and module inventory: `docs/index.md`

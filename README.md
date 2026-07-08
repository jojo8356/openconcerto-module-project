# OpenConcerto Project Module

Personal OpenConcerto module for project/affair management.

## Current Build

The module has been compiled and installed locally as:

```text
/home/jojokes/.local/share/OpenConcerto/Modules/org.openconcerto.modules.project-1.1.jar
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
- The affair list uses `DATE` for date ordering and exposes `DATE` as a list column.
- Runtime bytecode/JAR patch classes have been removed.

# Quick Start

Build with `alr build`. Run `bin/search ROOT PATTERN` for a deterministic combined search: results go to standard output, one a line (see `docs/search-semantics.md` for the format), and every diagnostic to standard error. It exits non-zero when the arguments are not a root and a pattern (it prints its usage then; `--help` prints it on standard output), when a root is missing or cannot be walked, or when the query is refused. `--version` prints the version. The GUI executable uses the same engine packages as the command entry point.

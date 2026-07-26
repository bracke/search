# search

`search` is an Ada 2022 desktop filesystem search application and reusable search engine.

The engine supports filename, path, content, combined, literal, regular-expression, multi-root, metadata-ready, and `.gitignore`-aware searches. GUI state is isolated in `Search_GUI` adapters so the engine remains deterministic, locale-neutral, and testable.

## Build

```sh
alr build
```

## Test

```sh
cd search_tests
alr run search_tests
alr run search_release_check
```

## Documentation

See `docs/` for quick start, user guide, architecture, public API, search semantics, query model, settings, saved searches, integration notes, testing, build, release, and AI-oriented documentation.

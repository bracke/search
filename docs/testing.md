# Testing

All automated tests are AUnit suites in `search_tests`. Coverage includes query validation, traversal, content search, regexp integration, localization keys, settings, persistence models, GUI model adapters, execution, cancellation, exports, the command-line program (`Search.Cli`), and release checks.

Content scanning (`Search_Tests.Content_Tests`) covers a 4 MiB single-line file (found, with a bounded preview), the file-size limit (`content.file.too_large`), binary detection from the first 8 KiB, UTF-16 decoding (BOM, surrogate pairs, U+FFFD for what cannot be decoded) and preview windows cut at UTF-8 boundaries.

The unreadable-root case of the command-line tests needs a folder this process cannot list, which an administrator (or Windows) cannot make; it then prints a `SKIPPED:` line. With `SEARCH_TEST_REQUIRE_UNREADABLE=1` -- set by the Linux CI job, whose runner is not root -- a skip is a failure instead.

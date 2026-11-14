# Search Semantics

Each filesystem object appears at most once per result set, however many of the query's roots reach it: roots that overlap (one inside another, or the same folder named twice) report what they share once, and a folder they share is walked once. An object is known by its folder's resolved path and its own name, so a link is an object of its own, not the thing it points to. Content matches are attached to the object result. Result identity (`Id`) is stable within a result set. Every result carries `Revision` 1: a search reports objects as it found them, and nothing refreshes a result once it is reported -- a later search is a new result set.

## Roots

A relative root is read from the query's base directory (`Set_Base_Directory`), or the process's current directory when none is set, and searched as the absolute path that makes; `.` and `..` are resolved from the text. A root that does not exist refuses the query (`query.root.not_found`); one that exists but cannot be walked is reported with the error `traversal.root.failed`, and an entry below a root that cannot be read with the warning `traversal.entry.failed`.

## Paths

Path matching (path and combined modes) matches an object's path relative to the root it was reached from, not its whole path: searching `~/notes` for `notes` by path finds what has `notes` in its path below `~/notes`, rather than everything, since every path there starts with the root. The root itself has no path below itself, so it is found by name only.

## Regular expressions

A regular expression matches names, paths and content a code point at a time (UTF-8), so `.` or a class such as `[éè]` takes a whole `é`. A name that is not UTF-8 is matched a byte at a time.

## Symbolic links

A root is walked whatever it is: it was named. Below a root, a symbolic link (on Windows, a symbolic link or a junction) is an object of its own, and the query's symlink policy says how far the walk goes through it:

- `Do_Not_Follow_Symlinks` (the default): the link is matched by its own name and path, like any entry, and nothing is read or walked through it. A link back up the tree cannot loop the walk, and a linked folder inside a root is not reported a second time under the link.
- `Follow_File_Symlinks`: as above, but a link to a file is also searched for content.
- `Follow_All_Symlinks`: links to folders are walked too, and every folder is walked at most once, known by its resolved path. A link loop ends where it comes back to a folder already walked, and a folder reached both directly and through a link is walked once, whichever way is met first.

## Case

A query that ignores case folds names, paths, lines and the pattern a code point at a time (Unicode simple lowercase mapping), so `Ä` matches `ä` and `ПРИВЕТ` matches `привет`. The pattern is folded once per query. Bytes that are not UTF-8 are compared as they are, and a character whose lowercase form takes a different number of bytes (the Kelvin sign, `İ`) is compared unfolded, so content match offsets stay byte offsets into the original line. Regular-expression queries fold through the regexp engine's own case-insensitive mode.

## Text output

The text format (`Export_Text`, what `bin/search` prints) writes one result a line: its path, then its match count in brackets. A path holding a control character -- a line break is legal in a POSIX name -- or starting with a double quote is written between double quotes, C-style: `\n`, `\r`, `\t`, `\"` and `\\`, and `\xHH` for any other control byte. Every other path is written as it is, so a Windows path keeps its backslashes and one line is always one result. JSON escapes every control character as `\u00XX` and writes a byte that is not UTF-8 as U+FFFD; CSV quotes every text field and doubles a quote in it.

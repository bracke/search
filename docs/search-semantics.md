# Search Semantics

Each filesystem object appears at most once per result set. Content matches are attached to the object result. Result identity is stable within a session and revisions describe refreshed state.

## Symbolic links

A root is walked whatever it is: it was named. Below a root, a symbolic link (on Windows, a symbolic link or a junction) is an object of its own, and the query's symlink policy says how far the walk goes through it:

- `Do_Not_Follow_Symlinks` (the default): the link is matched by its own name and path, like any entry, and nothing is read or walked through it. A link back up the tree cannot loop the walk, and a linked folder inside a root is not reported a second time under the link.
- `Follow_File_Symlinks`: as above, but a link to a file is also searched for content.
- `Follow_All_Symlinks`: links to folders are walked too, and every folder is walked at most once, known by its resolved path. A link loop ends where it comes back to a folder already walked, and a folder reached both directly and through a link is walked once, whichever way is met first.

## Case

A query that ignores case folds names, paths, lines and the pattern a code point at a time (Unicode simple lowercase mapping), so `Ä` matches `ä` and `ПРИВЕТ` matches `привет`. The pattern is folded once per query. Bytes that are not UTF-8 are compared as they are, and a character whose lowercase form takes a different number of bytes (the Kelvin sign, `İ`) is compared unfolded, so content match offsets stay byte offsets into the original line. Regular-expression queries fold through the regexp engine's own case-insensitive mode.

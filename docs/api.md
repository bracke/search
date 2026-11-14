# Public API

Use `Search.Queries.New_Builder`, setter procedures, and `Build` to create an immutable query. Validate with `Search.Queries.Validate`. Execute with `Search.Engine.Execute`. Export with `Search.Exports.Render`. A relative root is read from `Search.Queries.Set_Base_Directory`'s folder, or the process's current directory when none is set; `Search.Queries.Resolved_Root` gives the absolute root a search walks. `Search.Cli.Run` is the command-line program without its process: it returns what `bin/search` prints on each stream and whether it succeeds.

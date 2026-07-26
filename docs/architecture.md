# Architecture

`Search.Queries` owns immutable query values and structured validation. `Search.Engine` owns traversal, batching, cancellation, and session execution. `Search.Content` owns bounded content scanning. `Search_GUI` adapts immutable results to guikit grid and information-panel models.

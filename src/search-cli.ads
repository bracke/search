with Ada.Strings.Unbounded;

with Search.Queries;

--  What the command-line program does, apart from the process it runs in:
--  `search ROOT PATTERN` searches ROOT for PATTERN (by name, by path below
--  ROOT, and by content) and lists what it found in the text format
--  (Search.Exports). Kept apart from Search.Main so that what it prints, on
--  which stream, and whether it succeeds can be tested without starting a
--  process.
--
--  Every diagnostic the search reports is printed, one to a line, on the
--  error stream: "search: PATH: message". The run fails when the arguments
--  are not a root and a pattern (the usage is printed then), when the query
--  is refused (a missing root among them), and when a root could not be
--  walked; a single entry below a root that could not be read is reported
--  but does not fail the run.
package Search.Cli is

   type Outcome is record
      --  What goes to standard output.
      Output  : Ada.Strings.Unbounded.Unbounded_String;
      --  What goes to standard error.
      Errors  : Ada.Strings.Unbounded.Unbounded_String;
      --  Whether the program succeeded: its exit status.
      Success : Boolean := False;
   end record;

   --  Run the program on Arguments.
   --
   --  @param Arguments The command-line arguments, the program's name not
   --    among them: ROOT and PATTERN; "--help" (or "-h") or "--version"
   --    alone.
   --  @param Base_Directory The folder a relative ROOT is read from; "" for
   --    the process's current directory.
   --  @return What to print, and whether the run succeeded.
   function Run
     (Arguments      : Search.Queries.String_Vectors.Vector;
      Base_Directory : String := "")
      return Outcome;

end Search.Cli;

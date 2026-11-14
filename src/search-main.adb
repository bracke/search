with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Search.Cli;
with Search.Queries;

--  The command-line program: Search.Cli does the work, and this hands it the
--  arguments and puts what it says on the streams it names.
procedure Search.Main is
   Arguments : Search.Queries.String_Vectors.Vector;
begin
   for Index in 1 .. Ada.Command_Line.Argument_Count loop
      Arguments.Append (To_Unbounded_String (Ada.Command_Line.Argument (Index)));
   end loop;

   declare
      Result : constant Search.Cli.Outcome := Search.Cli.Run (Arguments);
   begin
      Ada.Text_IO.Put (To_String (Result.Output));
      Ada.Text_IO.Put (Ada.Text_IO.Standard_Error, To_String (Result.Errors));
      if not Result.Success then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end;
end Search.Main;

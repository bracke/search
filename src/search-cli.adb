with Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Search.Engine;
with Search.Exports;
with Search.Messages;
with Search.Types;

package body Search.Cli is
   use type Ada.Containers.Count_Type;
   use type Search.Types.Completion_State;
   use type Search.Types.Diagnostic_Severity;

   --  The usage, as the catalogue words it.
   function Usage return String is
     (Search.Messages.Text ("cli.usage") & ASCII.LF & Search.Messages.Text ("cli.summary") & ASCII.LF);

   --  One diagnostic as a line of the error stream: the program's name, the
   --  path it is about when it is about one, and its message.
   function Line_Of (Diagnostic : Search.Types.Diagnostic) return String is
      Path : constant String := To_String (Diagnostic.Path);
   begin
      return Search.Messages.Text ("app.name") & ": "
        & (if Path = "" then "" else Path & ": ")
        & Search.Messages.Text ("diagnostic." & To_String (Diagnostic.Code)) & ASCII.LF;
   end Line_Of;

   function Run
     (Arguments      : Search.Queries.String_Vectors.Vector;
      Base_Directory : String := "")
      return Outcome
   is
      Result : Outcome;
   begin
      if Arguments.Length = 1 and then To_String (Arguments (1)) in "--help" | "-h" then
         Result.Output := To_Unbounded_String (Usage);
         Result.Success := True;
         return Result;
      elsif Arguments.Length = 1 and then To_String (Arguments (1)) = "--version" then
         Result.Output := To_Unbounded_String (Search.Messages.Text ("app.name") & " " & Search.Version & ASCII.LF);
         Result.Success := True;
         return Result;
      elsif Arguments.Length /= 2 then
         Result.Errors := To_Unbounded_String (Usage);
         return Result;
      end if;

      declare
         Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
         Token   : aliased Search.Engine.Cancellation_Token;
         Found   : Search.Types.Result_Vectors.Vector;
         Summary : Search.Engine.Execution_Summary;

         procedure Collect (Batch : Search.Types.Result_Batch) is
         begin
            for Item of Batch.Results loop
               Found.Append (Item);
            end loop;
         end Collect;
      begin
         Search.Queries.Add_Root (Builder, To_String (Arguments (1)));
         Search.Queries.Set_Pattern (Builder, To_String (Arguments (2)));
         Search.Queries.Set_Mode (Builder, Search.Types.Combined_Mode);
         Search.Queries.Set_Base_Directory (Builder, Base_Directory);
         Summary := Search.Engine.Execute (Search.Queries.Build (Builder), Token'Access, Collect'Access);

         Result.Success := Summary.State = Search.Types.Completed;
         for Diagnostic of Summary.Diagnostics loop
            Append (Result.Errors, Line_Of (Diagnostic));
            if Diagnostic.Severity = Search.Types.Error then
               Result.Success := False;
            end if;
         end loop;
         --  What was found is listed even when a root failed: the others
         --  were searched, and the status says the run was not whole.
         if Summary.State /= Search.Types.Failed then
            Result.Output := To_Unbounded_String (Search.Exports.Render (Found, Search.Types.Export_Text));
         end if;
      end;
      return Result;
   end Run;

end Search.Cli;

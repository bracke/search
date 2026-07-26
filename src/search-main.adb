with Ada.Command_Line;
with Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Search;
with Search.Engine;
with Search.Exports;
with Search.Messages;
with Search.Queries;
with Search.Types;
use type Search.Types.Completion_State;

procedure Search.Main is
   Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
   Token   : aliased Search.Engine.Cancellation_Token;
   Results : Search.Types.Result_Vectors.Vector;

   procedure Collect (Batch : Search.Types.Result_Batch) is
   begin
      for Result of Batch.Results loop
         Results.Append (Result);
      end loop;
   end Collect;

   Summary : Search.Engine.Execution_Summary;
begin
   if Ada.Command_Line.Argument_Count < 2 then
      Ada.Text_IO.Put_Line
        (Search.Messages.Text ("app.name") & " " & Search.Version);
      return;
   end if;

   Search.Queries.Add_Root (Builder, Ada.Command_Line.Argument (1));
   Search.Queries.Set_Pattern (Builder, Ada.Command_Line.Argument (2));
   Search.Queries.Set_Mode (Builder, Search.Types.Combined_Mode);

   Summary := Search.Engine.Execute
     (Search.Queries.Build (Builder),
      Token'Access,
      Collect'Access);

   if Summary.State = Search.Types.Completed then
      Ada.Text_IO.Put (Search.Exports.Render (Results, Search.Types.Export_Text));
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Search.Main;

with Ada.Directories;
with Ada.Text_IO;

with AUnit.Assertions; use AUnit.Assertions;

with Search.Engine;
with Search.Queries;
with Search.Types;

package body Search_Tests.Engine_Tests is
   use type Search.Types.Completion_State;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("execution engine");
   end Name;

   procedure Write_File (Path : String; Text : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (File, Text);
      Ada.Text_IO.Close (File);
   end Write_File;

   procedure Test_Content_Search (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root    : constant String := "search_engine_fixture";
      Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
      Token   : aliased Search.Engine.Cancellation_Token;
      Summary : Search.Engine.Execution_Summary;
   begin
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Directory (Root);
      end if;
      Write_File (Root & "/alpha.txt", "needle" & ASCII.LF & "hay");
      Search.Queries.Add_Root (Builder, Root);
      Search.Queries.Set_Pattern (Builder, "needle");
      Search.Queries.Set_Mode (Builder, Search.Types.Content_Mode);
      Summary := Search.Engine.Execute (Search.Queries.Build (Builder), Token'Access);
      Assert (Summary.State = Search.Types.Completed, "content search completed");
      Assert (Summary.Result_Count = 1, "content result counted");
      Ada.Directories.Delete_File (Root & "/alpha.txt");
      Ada.Directories.Delete_Directory (Root);
   end Test_Content_Search;

   procedure Test_Cancellation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
      Token   : aliased Search.Engine.Cancellation_Token;
      Summary : Search.Engine.Execution_Summary;
   begin
      Search.Queries.Add_Root (Builder, ".");
      Search.Queries.Set_Pattern (Builder, "anything");
      Token.Cancel;
      Summary := Search.Engine.Execute (Search.Queries.Build (Builder), Token'Access);
      Assert (Summary.State = Search.Types.Cancelled, "cancel token stops execution");
   end Test_Cancellation;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Content_Search'Access, "content search");
      Register_Routine (T, Test_Cancellation'Access, "cancellation");
   end Register_Tests;
end Search_Tests.Engine_Tests;

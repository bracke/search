with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Search.Types;
with Search_GUI;

package body Search_Tests.Gui_Tests is
   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("gui model");
   end Name;

   procedure Test_Rows_And_Info (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Results : Search.Types.Result_Vectors.Vector;
      Rows    : Search_GUI.Row_Vectors.Vector;
   begin
      Results.Append
        (Search.Types.Search_Result'
           (Id           => 1,
            Root         => To_Unbounded_String ("."),
            Path         => To_Unbounded_String ("./alpha.txt"),
            Name         => To_Unbounded_String ("alpha.txt"),
            Size         => 1,
            Is_Directory => False,
            Match_Count  => 1,
            Matches      => <>,
            Freshness    => Search.Types.Fresh,
            Revision     => 1,
            Diagnostics  => <>));
      Rows := Search_GUI.To_Rows (Results);
      Assert (Natural (Rows.Length) = 1, "row adapter preserves result");
      Assert (Natural (Search_GUI.To_Grid_Items (Rows).Length) = 1, "grid adapter uses guikit item model");
      Assert (Search_GUI.Build_Info_Panel (Results.First_Element).Match_Count = 1, "info panel model");
      Assert (Search_GUI.Command_Key (Search_GUI.Search_Command) = "command.search", "localized command key");
      Assert (Search_GUI.Command_Label (Search_GUI.Search_Command) = "Search",
              "command label resolves through the message catalog");
   end Test_Rows_And_Info;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Rows_And_Info'Access, "rows and info panel");
   end Register_Tests;
end Search_Tests.Gui_Tests;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Search.Exports;
with Search.Types;

package body Search_Tests.Export_Tests is
   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("exports");
   end Name;

   procedure Test_Formats (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Results : Search.Types.Result_Vectors.Vector;
   begin
      Results.Append
        (Search.Types.Search_Result'
           (Id           => 1,
            Root         => To_Unbounded_String ("."),
            Path         => To_Unbounded_String ("./alpha.txt"),
            Name         => To_Unbounded_String ("alpha.txt"),
            Size         => 1,
            Is_Directory => False,
            Match_Count  => 2,
            Matches      => <>,
            Freshness    => Search.Types.Fresh,
            Revision     => 1,
            Diagnostics  => <>));
      Assert (Search.Exports.Render (Results, Search.Types.Export_JSON)'Length > 0, "json export");
      Assert (Search.Exports.Render (Results, Search.Types.Export_CSV)'Length > 0, "csv export");
      Assert (Search.Exports.Render (Results, Search.Types.Export_Text)'Length > 0, "text export");
   end Test_Formats;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Formats'Access, "structured formats");
   end Register_Tests;
end Search_Tests.Export_Tests;

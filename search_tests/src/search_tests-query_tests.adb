with AUnit.Assertions; use AUnit.Assertions;

with Search.Queries;
with Search.Types;

package body Search_Tests.Query_Tests is
   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("query validation");
   end Name;

   procedure Test_Missing_Root_And_Pattern (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Query : constant Search.Queries.Query := Search.Queries.Build (Search.Queries.New_Builder);
      Diagnostics : constant Search.Types.Diagnostic_Vectors.Vector := Search.Queries.Validate (Query);
   begin
      Assert (Natural (Diagnostics.Length) = 2, "missing root and pattern are structured diagnostics");
   end Test_Missing_Root_And_Pattern;

   procedure Test_Regex_Validation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
   begin
      Search.Queries.Add_Root (Builder, ".");
      Search.Queries.Set_Pattern (Builder, "[");
      Search.Queries.Set_Text_Mode (Builder, Search.Types.Regular_Expression);
      Assert (not Search.Queries.Validate (Search.Queries.Build (Builder)).Is_Empty, "invalid regex reported");
   end Test_Regex_Validation;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Missing_Root_And_Pattern'Access, "missing root and pattern");
      Register_Routine (T, Test_Regex_Validation'Access, "regexp validation");
   end Register_Tests;
end Search_Tests.Query_Tests;

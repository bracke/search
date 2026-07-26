with AUnit.Test_Cases;

with Search_Tests.Query_Tests;
with Search_Tests.Engine_Tests;
with Search_Tests.Export_Tests;
with Search_Tests.Gui_Tests;
with Search_Tests.Settings_Tests;

package body Search_Tests.Suite is
   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Search_Tests.Query_Tests.Test_Case));
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Search_Tests.Engine_Tests.Test_Case));
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Search_Tests.Export_Tests.Test_Case));
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Search_Tests.Gui_Tests.Test_Case));
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Search_Tests.Settings_Tests.Test_Case));
      return Result;
   end Suite;
end Search_Tests.Suite;

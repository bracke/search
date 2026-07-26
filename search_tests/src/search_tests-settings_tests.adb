with Ada.Calendar;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Search.Queries;
with Search.Settings;
with Search.Types;

package body Search_Tests.Settings_Tests is
   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("settings persistence model");
   end Name;

   procedure Test_History_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      History : Search.Settings.History_Vectors.Vector;
   begin
      for I in 1 .. 5 loop
         Search.Settings.Add_History
           (History,
            (Timestamp   => Ada.Calendar.Clock,
             State       => Search.Types.Completed,
             Duration_Ms => I),
            Limit => 3);
      end loop;
      Assert (Natural (History.Length) = 3, "bounded history");
   end Test_History_Bounds;

   procedure Test_Saved_Search_Delete (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Items : Search.Settings.Saved_Search_Vectors.Vector;
      Query : constant Search.Queries.Query := Search.Queries.Build (Search.Queries.New_Builder);
   begin
      Search.Settings.Add_Saved_Search
        (Items,
         (Name => To_Unbounded_String ("daily"), Query => Query, View_Mode => To_Unbounded_String ("details")));
      Search.Settings.Delete_Saved_Search (Items, "daily");
      Assert (Items.Is_Empty, "saved search delete");
   end Test_Saved_Search_Delete;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_History_Bounds'Access, "history bounds");
      Register_Routine (T, Test_Saved_Search_Delete'Access, "saved searches");
   end Register_Tests;
end Search_Tests.Settings_Tests;

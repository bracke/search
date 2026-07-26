with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;

procedure Search_Release_Check is
   Errors : Natural := 0;

   procedure Require_File (Path : String) is
   begin
      if not Ada.Directories.Exists (Path) then
         Ada.Text_IO.Put_Line ("missing: " & Path);
         Errors := Errors + 1;
      end if;
   end Require_File;

begin
   Require_File ("../README.md");
   Require_File ("../docs/architecture.md");
   Require_File ("../docs/testing.md");
   Require_File ("../docs/release.md");
   Require_File ("../share/search.catalog");
   --  The build bundles the load-only i18n data into share/i18n (tools/i18n_bundle);
   --  search renders its catalog through the messages crate, which needs it.
   Require_File ("../share/i18n/formats.i18ndata");
   Require_File ("../examples/filename_search.adb");
   Require_File ("src/search_tests-query_tests.adb");
   Require_File ("src/search_tests-engine_tests.adb");
   Require_File ("src/search_tests-gui_tests.adb");

   if Errors > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Search_Release_Check;

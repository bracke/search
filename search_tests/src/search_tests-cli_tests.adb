with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with AUnit.Assertions; use AUnit.Assertions;

with Hostkit.Fs;
with Hostkit.Host;
with Hostkit.Metadata;

with Search.Cli;
with Search.Queries;

--  The command-line program as Search.Cli runs it: what it prints on which
--  stream, and whether it succeeds -- without starting a process.
package body Search_Tests.Cli_Tests is
   use type Hostkit.Host.Kind;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("command line");
   end Name;

   function Arguments (First : String := ""; Second : String := ""; Third : String := "")
     return Search.Queries.String_Vectors.Vector
   is
      Result : Search.Queries.String_Vectors.Vector;

      procedure Add (Item : String) is
      begin
         if Item /= "" then
            Result.Append (To_Unbounded_String (Item));
         end if;
      end Add;
   begin
      Add (First);
      Add (Second);
      Add (Third);
      return Result;
   end Arguments;

   function Contains (Text : Unbounded_String; Part : String) return Boolean is
     (Ada.Strings.Fixed.Index (To_String (Text), Part) > 0);

   procedure Test_Usage (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      type Argument_Lists is array (Positive range <>) of Search.Queries.String_Vectors.Vector;
      Usage  : constant String := "Usage: search ROOT PATTERN";
      Wrongs : constant Argument_Lists := [Arguments, Arguments ("only-a-root"), Arguments ("a", "b", "c")];
   begin
      for Wrong of Wrongs loop
         declare
            Result : constant Search.Cli.Outcome := Search.Cli.Run (Wrong);
         begin
            Assert (not Result.Success, "a wrong number of arguments fails");
            Assert (Contains (Result.Errors, Usage),
                    "and prints the usage on the error stream: " & To_String (Result.Errors));
            Assert (Length (Result.Output) = 0, "and nothing on standard output");
         end;
      end loop;
      declare
         Result : constant Search.Cli.Outcome := Search.Cli.Run (Arguments ("--help"));
      begin
         Assert (Result.Success, "--help succeeds");
         Assert (Contains (Result.Output, Usage), "and prints the usage on standard output");
      end;
      declare
         Result : constant Search.Cli.Outcome := Search.Cli.Run (Arguments ("--version"));
      begin
         Assert (Result.Success and then Contains (Result.Output, "search"), "--version prints the version");
      end;
   end Test_Usage;

   procedure Test_Missing_Root (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root   : constant String := Hostkit.Fs.Create_Temporary_Directory ("search-cli-test");
      Gone   : constant String := Hostkit.Fs.Join (Root, "no-such-folder");
      Result : constant Search.Cli.Outcome := Search.Cli.Run (Arguments (Gone, "x"));
      Ignore : Hostkit.Fs.Delete_Tree_Outcome;
   begin
      Ignore := Hostkit.Fs.Delete_Tree_No_Follow (Root);
      Assert (not Result.Success, "a missing root fails the run");
      Assert (Contains (Result.Errors, Gone), "the error names the root: " & To_String (Result.Errors));
      Assert (Contains (Result.Errors, "The search root does not exist."),
              "and says what is wrong with it, from the catalogue: " & To_String (Result.Errors));
   end Test_Missing_Root;

   procedure Test_Finds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root   : constant String := Hostkit.Fs.Create_Temporary_Directory ("search-cli-test");
      File   : Ada.Text_IO.File_Type;
      Ignore : Hostkit.Fs.Delete_Tree_Outcome;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Hostkit.Fs.Join (Root, "needle.txt"));
      Ada.Text_IO.Close (File);
      declare
         --  ".", read from the fixture without changing this process's
         --  current directory.
         Result : constant Search.Cli.Outcome := Search.Cli.Run (Arguments (".", "needle"), Base_Directory => Root);
      begin
         Ignore := Hostkit.Fs.Delete_Tree_No_Follow (Root);
         Assert (Result.Success, "a search that finds something succeeds: " & To_String (Result.Errors));
         Assert (Contains (Result.Output, "needle.txt [1]"), "and lists it: " & To_String (Result.Output));
         Assert (Length (Result.Errors) = 0, "with nothing on the error stream");
      end;
      Assert (not Ada.Directories.Exists (Root), "the fixture is gone");
   end Test_Finds;

   --  Whether the folder at Path can be listed by this process.
   function Can_List (Path : String) return Boolean is
      Listing : Ada.Directories.Search_Type;
   begin
      Ada.Directories.Start_Search (Listing, Path, "");
      Ada.Directories.End_Search (Listing);
      return True;
   exception
      when others =>
         return False;
   end Can_List;

   --  A root that exists but cannot be walked fails the run. Taking a
   --  folder's read permission away is a mode change on POSIX; an
   --  administrator (root in a container) reads it anyway, and then there is
   --  nothing to check.
   procedure Test_Unreadable_Root (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root   : constant String := Hostkit.Fs.Create_Temporary_Directory ("search-cli-test");
      Closed : constant String := Hostkit.Fs.Join (Root, "closed");
      Ignore : Hostkit.Fs.Delete_Tree_Outcome;
   begin
      Ada.Directories.Create_Directory (Closed);
      if Hostkit.Host.Current = Hostkit.Host.Windows
        or else not Hostkit.Metadata.Set_Permissions (Closed, 0)
        or else Can_List (Closed)
      then
         Ignore := Hostkit.Fs.Delete_Tree_No_Follow (Root);
         return;
      end if;
      declare
         Result          : constant Search.Cli.Outcome := Search.Cli.Run (Arguments (Closed, "x"));
         Ignore_Restored : constant Boolean := Hostkit.Metadata.Set_Permissions (Closed, 8#700#);
      begin
         Ignore := Hostkit.Fs.Delete_Tree_No_Follow (Root);
         Assert (not Result.Success, "a root that cannot be walked fails the run");
         Assert (Contains (Result.Errors, "The search root could not be read."),
                 "and says so: " & To_String (Result.Errors));
      end;
   end Test_Unreadable_Root;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Usage'Access, "a wrong argument count prints the usage and fails");
      Register_Routine (T, Test_Missing_Root'Access, "a missing root is reported and fails the run");
      Register_Routine (T, Test_Finds'Access, "what is found goes to standard output");
      Register_Routine (T, Test_Unreadable_Root'Access, "a root that cannot be walked fails the run");
   end Register_Tests;
end Search_Tests.Cli_Tests;

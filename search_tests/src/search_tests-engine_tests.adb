with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with AUnit.Assertions; use AUnit.Assertions;

with Hostkit.Fs;

with Search.Engine;
with Search.Queries;
with Search.Text_Fold;
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
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path, Form => "shared=no");
      Ada.Text_IO.Put (File, Text);
      Ada.Text_IO.Close (File);
   end Write_File;

   --  Each fixture is a fresh folder of its own under the host's temporary
   --  folder, removed afterwards whatever happened -- never a fixed name in the
   --  current directory, which a failed run used to leave behind for the next
   --  one to reuse. Deleting never follows a link, so a fixture holding a link
   --  loop (or a link out of the tree) is removed safely.
   generic
      with procedure Body_Of_Test (Root : String);
   procedure With_Fixture;

   procedure With_Fixture is
      Root : constant String := Hostkit.Fs.Create_Temporary_Directory ("search-engine-test");

      procedure Clean_Up is
         Ignore : Hostkit.Fs.Delete_Tree_Outcome;
      begin
         if Root /= "" then
            Ignore := Hostkit.Fs.Delete_Tree_No_Follow (Root);
         end if;
      end Clean_Up;
   begin
      Assert (Root /= "", "a temporary fixture folder was made");
      Body_Of_Test (Root);
      Clean_Up;
   exception
      when others =>
         Clean_Up;
         raise;
   end With_Fixture;

   function Run
     (Root           : String;
      Pattern        : String;
      Mode           : Search.Types.Search_Mode;
      Case_Sensitive : Boolean := False;
      Policy         : Search.Types.Symlink_Policy := Search.Types.Do_Not_Follow_Symlinks)
      return Search.Engine.Execution_Summary
   is
      Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
      Token   : aliased Search.Engine.Cancellation_Token;
   begin
      Search.Queries.Add_Root (Builder, Root);
      Search.Queries.Set_Pattern (Builder, Pattern);
      Search.Queries.Set_Mode (Builder, Mode);
      Search.Queries.Set_Case_Sensitive (Builder, Case_Sensitive);
      Search.Queries.Set_Symlink_Policy (Builder, Policy);
      return Search.Engine.Execute (Search.Queries.Build (Builder), Token'Access);
   end Run;

   procedure Content_Search (Root : String) is
      Summary : Search.Engine.Execution_Summary;
   begin
      Write_File (Hostkit.Fs.Join (Root, "alpha.txt"), "needle" & ASCII.LF & "hay");
      Summary := Run (Root, "needle", Search.Types.Content_Mode);
      Assert (Summary.State = Search.Types.Completed, "content search completed");
      Assert (Summary.Result_Count = 1, "content result counted");
   end Content_Search;

   procedure Test_Content_Search (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Run_Test is new With_Fixture (Content_Search);
   begin
      Run_Test;
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

   --  Cancelling while the walk is under way stops it there: the per-batch
   --  callback, which the walk calls from inside itself, cancels after the
   --  first result, and the walk must notice before it has visited the rest.
   procedure Cancel_Mid_Walk (Root : String) is
      Total   : constant := 200;
      Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
      Token   : aliased Search.Engine.Cancellation_Token;
      Summary : Search.Engine.Execution_Summary;
      Batches : Natural := 0;

      procedure Cancel_After_First (Batch : Search.Types.Result_Batch) is
      begin
         if not Batch.Results.Is_Empty then
            Batches := Batches + 1;
            Token.Cancel;
         end if;
      end Cancel_After_First;
   begin
      for Index in 1 .. Total loop
         Write_File
           (Hostkit.Fs.Join
              (Root, "match-" & Ada.Strings.Fixed.Trim (Natural'Image (Index), Ada.Strings.Left) & ".txt"),
            "x");
      end loop;

      Search.Queries.Add_Root (Builder, Root);
      Search.Queries.Set_Pattern (Builder, "match");
      Search.Queries.Set_Mode (Builder, Search.Types.Filename_Mode);
      Summary :=
        Search.Engine.Execute
          (Search.Queries.Build (Builder), Token'Access, Cancel_After_First'Access, Batch_Size => 1);

      Assert (Batches >= 1, "the walk delivered a result before it was cancelled");
      Assert (Summary.State = Search.Types.Cancelled, "a cancel during the walk ends it as cancelled");
      Assert (Summary.Result_Count < Total,
              "the walk stopped early: " & Natural'Image (Summary.Result_Count) & " of" & Natural'Image (Total));
   end Cancel_Mid_Walk;

   procedure Test_Cancellation_Mid_Walk (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Run_Test is new With_Fixture (Cancel_Mid_Walk);
   begin
      Run_Test;
   end Test_Cancellation_Mid_Walk;

   --  A link back up the tree: Root/a/loop -> Root. Followed, the walk used to
   --  recurse round it without end; each object must be met at most once.
   procedure Link_Loop (Root : String) is
      Folder : constant String := Hostkit.Fs.Join (Root, "a");
      Link   : constant String := Hostkit.Fs.Join (Folder, "loop");
   begin
      Ada.Directories.Create_Directory (Folder);
      Write_File (Hostkit.Fs.Join (Folder, "needle.txt"), "needle");
      if not Hostkit.Fs.Create_Link (Target => Root, Link_Path => Link) then
         --  Windows without Developer Mode or the privilege refuses links, which
         --  is a normal answer there: there is then no loop to walk.
         return;
      end if;

      declare
         Summary : constant Search.Engine.Execution_Summary :=
           Run (Root, "needle", Search.Types.Filename_Mode);
      begin
         Assert (Summary.State = Search.Types.Completed, "a walk not following links completes");
         Assert (Summary.Result_Count = 1, "the file is found once, not again through the link:"
                 & Natural'Image (Summary.Result_Count));
      end;

      declare
         Summary : constant Search.Engine.Execution_Summary := Run (Root, "loop", Search.Types.Filename_Mode);
      begin
         Assert (Summary.Result_Count = 1, "the link itself is an entry, found by its name");
      end;

      declare
         Summary : constant Search.Engine.Execution_Summary :=
           Run (Root, "needle", Search.Types.Filename_Mode, Policy => Search.Types.Follow_All_Symlinks);
      begin
         Assert (Summary.State = Search.Types.Completed, "a walk following links ends at the loop");
         Assert (Summary.Result_Count = 1, "following the loop does not find the file again:"
                 & Natural'Image (Summary.Result_Count));
      end;
   end Link_Loop;

   procedure Test_Link_Loop (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Run_Test is new With_Fixture (Link_Loop);
   begin
      Run_Test;
   end Test_Link_Loop;

   Upper_A_Umlaut : constant String := Character'Val (16#C3#) & Character'Val (16#84#);  --  Ä
   Lower_A_Umlaut : constant String := Character'Val (16#C3#) & Character'Val (16#A4#);  --  ä
   --  U+3104 BOPOMOFO LETTER P: E3 84 84. Byte-wise Latin-1 lowering turned the
   --  lead byte of "Ä" (C3) into E3, so "Ä" became E3 84 and matched in here.
   Bopomofo_P     : constant String :=
     Character'Val (16#E3#) & Character'Val (16#84#) & Character'Val (16#84#);
   --  "ПРИВЕТ" and "привет".
   Privet_Upper   : constant String :=
     [Character'Val (16#D0#), Character'Val (16#9F#), Character'Val (16#D0#), Character'Val (16#A0#),
      Character'Val (16#D0#), Character'Val (16#98#), Character'Val (16#D0#), Character'Val (16#92#),
      Character'Val (16#D0#), Character'Val (16#95#), Character'Val (16#D0#), Character'Val (16#A2#)];
   Privet_Lower   : constant String :=
     [Character'Val (16#D0#), Character'Val (16#BF#), Character'Val (16#D1#), Character'Val (16#80#),
      Character'Val (16#D0#), Character'Val (16#B8#), Character'Val (16#D0#), Character'Val (16#B2#),
      Character'Val (16#D0#), Character'Val (16#B5#), Character'Val (16#D1#), Character'Val (16#82#)];

   procedure Test_Fold (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Search.Text_Fold;
   begin
      Assert (Fold ("ReadMe.TXT") = "readme.txt", "ASCII folds");
      Assert (Fold (Upper_A_Umlaut) = Lower_A_Umlaut, "A-umlaut folds to a-umlaut");
      Assert (Fold (Lower_A_Umlaut) = Lower_A_Umlaut, "a-umlaut stays a-umlaut");
      Assert (Fold (Privet_Upper) = Privet_Lower, "Cyrillic folds");
      Assert (Fold (Bopomofo_P) = Bopomofo_P, "a caseless character is unchanged");
      Assert (Ada.Strings.Fixed.Index (Fold ("x" & Bopomofo_P & "y"), Fold (Upper_A_Umlaut)) = 0,
              "C3 84 (A-umlaut) does not match inside E3 84 84");
      Assert (Fold (Character'Val (16#C3#) & "A") = Character'Val (16#C3#) & "a",
              "a stray lead byte is kept as it is and the rest still folds");
      Assert (Fold ("") = "", "nothing folds to nothing");
   end Test_Fold;

   procedure Unicode_Content (Root : String) is
   begin
      Write_File (Hostkit.Fs.Join (Root, "fruit.txt"), "Gr" & Upper_A_Umlaut & "N: " & Upper_A_Umlaut & "PFEL");
      Write_File (Hostkit.Fs.Join (Root, "greeting.txt"), Privet_Upper & ", world");
      Write_File (Hostkit.Fs.Join (Root, "bopomofo.txt"), "letters " & Bopomofo_P & " here");

      Assert (Run (Root, Lower_A_Umlaut & "pfel", Search.Types.Content_Mode).Result_Count = 1,
              "a-umlaut-pfel finds A-UMLAUT-PFEL when case is ignored");
      Assert (Run (Root, Lower_A_Umlaut & "pfel", Search.Types.Content_Mode, Case_Sensitive => True).Result_Count = 0,
              "a-umlaut-pfel does not find A-UMLAUT-PFEL when case matters");
      Assert (Run (Root, Privet_Lower, Search.Types.Content_Mode).Result_Count = 1,
              "Cyrillic privet finds PRIVET");
      Assert (Run (Root, Upper_A_Umlaut, Search.Types.Content_Mode).Result_Count = 1,
              "A-umlaut finds only the file with one, not the one with E3 84 84");
   end Unicode_Content;

   procedure Test_Unicode_Content (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Run_Test is new With_Fixture (Unicode_Content);
   begin
      Run_Test;
   end Test_Unicode_Content;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Content_Search'Access, "content search");
      Register_Routine (T, Test_Cancellation'Access, "cancellation before the walk");
      Register_Routine (T, Test_Cancellation_Mid_Walk'Access, "cancellation during the walk stops it early");
      Register_Routine (T, Test_Link_Loop'Access, "a link loop is walked through at most once");
      Register_Routine (T, Test_Fold'Access, "case folding is per code point");
      Register_Routine (T, Test_Unicode_Content'Access, "case-insensitive content search folds Unicode");
   end Register_Tests;
end Search_Tests.Engine_Tests;

with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Hostkit.Fs;

with Search.Content;
with Search.Engine;
with Search.Queries;
with Search.Types;

package body Search_Tests.Content_Tests is
   use type Search.Types.Completion_State;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("content scanning");
   end Name;

   function Byte (Value : Natural) return Character is (Character'Val (Value));

   E_Acute     : constant String := [Byte (16#C3#), Byte (16#A9#)];                              --  U+00E9
   Zhong       : constant String := [Byte (16#E4#), Byte (16#B8#), Byte (16#AD#)];               --  U+4E2D
   Grin        : constant String := [Byte (16#F0#), Byte (16#9F#), Byte (16#98#), Byte (16#80#)];  --  U+1F600
   Replacement : constant String := [Byte (16#EF#), Byte (16#BF#), Byte (16#BD#)];               --  U+FFFD
   Ellipsis    : constant String := [Byte (16#E2#), Byte (16#80#), Byte (16#A6#)];               --  U+2026

   function Repeat (Text : String; Count : Natural) return String is (Ada.Strings.Fixed."*" (Count, Text));

   --  Code units as UTF-16 bytes.
   type Unit_List is array (Positive range <>) of Natural;

   function UTF_16 (Units : Unit_List; Big_Endian : Boolean) return String is
      Result : String (1 .. 2 * Units'Length);
   begin
      for I in Units'Range loop
         declare
            High : constant Character := Byte (Units (I) / 256);
            Low  : constant Character := Byte (Units (I) mod 256);
            At_I : constant Positive := 2 * (I - Units'First) + 1;
         begin
            Result (At_I .. At_I + 1) := (if Big_Endian then [High, Low] else [Low, High]);
         end;
      end loop;
      return Result;
   end UTF_16;

   --  "café 中 😀 end" as UTF-16 code units, with a byte order mark.
   Sample_Units : constant Unit_List :=
     [16#FEFF#, Character'Pos ('c'), Character'Pos ('a'), Character'Pos ('f'), 16#E9#, 16#20#,
      16#4E2D#, 16#20#, 16#D83D#, 16#DE00#, 16#20#, Character'Pos ('e'), Character'Pos ('n'),
      Character'Pos ('d')];
   Sample_UTF_8 : constant String := "caf" & E_Acute & " " & Zhong & " " & Grin & " end";

   function Decoded (Text : String; Big_Endian : Boolean) return String is
      Buffer : String (1 .. Search.Content.UTF_8_Capacity (Text'Length));
      Last   : Natural;
   begin
      Search.Content.Decode_UTF_16 (Text, Big_Endian, Buffer, Last);
      return Buffer (1 .. Last);
   end Decoded;

   procedure Write_Bytes (Path : String; Text : String) is
      use Ada.Streams.Stream_IO;
      File : File_Type;
   begin
      Create (File, Out_File, Path);
      String'Write (Stream (File), Text);
      Close (File);
   end Write_Bytes;

   --  One line: Before bytes of 'x', Middle, then After bytes of 'x' -- written
   --  a block at a time, so the test's own stack holds no line of that size.
   procedure Write_Long_Line (Path : String; Before : Natural; Middle : String; After : Natural) is
      use Ada.Streams.Stream_IO;
      File   : File_Type;
      Filler : constant String (1 .. 64 * 1024) := [others => 'x'];

      procedure Fill (Count : Natural) is
         Left : Natural := Count;
      begin
         while Left > 0 loop
            String'Write (Stream (File), Filler (1 .. Natural'Min (Left, Filler'Length)));
            Left := Left - Natural'Min (Left, Filler'Length);
         end loop;
      end Fill;
   begin
      Create (File, Out_File, Path);
      Fill (Before);
      String'Write (Stream (File), Middle);
      Fill (After);
      Close (File);
   end Write_Long_Line;

   generic
      with procedure Body_Of_Test (Root : String);
   procedure With_Fixture;

   procedure With_Fixture is
      Root : constant String := Hostkit.Fs.Create_Temporary_Directory ("search-content-test");

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

   type Outcome is record
      Summary : Search.Engine.Execution_Summary;
      Results : Search.Types.Result_Vectors.Vector;
   end record;

   function Search_For
     (Root           : String;
      Pattern        : String;
      Mode           : Search.Types.Search_Mode := Search.Types.Content_Mode;
      Case_Sensitive : Boolean := False;
      Max_File_Size  : Long_Long_Integer := -1)
      return Outcome
   is
      Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
      Token   : aliased Search.Engine.Cancellation_Token;
      Result  : Outcome;

      procedure Collect (Batch : Search.Types.Result_Batch) is
      begin
         for Item of Batch.Results loop
            Result.Results.Append (Item);
         end loop;
      end Collect;
   begin
      Search.Queries.Add_Root (Builder, Root);
      Search.Queries.Set_Pattern (Builder, Pattern);
      Search.Queries.Set_Mode (Builder, Mode);
      Search.Queries.Set_Case_Sensitive (Builder, Case_Sensitive);
      if Max_File_Size >= 0 then
         Search.Queries.Set_Max_File_Size (Builder, Max_File_Size);
      end if;
      Result.Summary := Search.Engine.Execute (Search.Queries.Build (Builder), Token'Access, Collect'Access);
      return Result;
   end Search_For;

   function Has_Diagnostic (Diagnostics : Search.Types.Diagnostic_Vectors.Vector; Code : String) return Boolean is
   begin
      for Diagnostic of Diagnostics loop
         if To_String (Diagnostic.Code) = Code then
            return True;
         end if;
      end loop;
      return False;
   end Has_Diagnostic;

   --  A 4 MiB line is searched like any other: the scan once copied each line
   --  onto the walking task's stack, and a line that size overflowed it and
   --  lost the file's matches. The match's preview is a window of the line,
   --  not all 4 MiB of it.
   procedure Long_Line (Root : String) is
      Half    : constant := 2 * 1024 * 1024;
      Context : constant String := Repeat ("x", Search.Content.Preview_Context);
   begin
      Write_Long_Line (Hostkit.Fs.Join (Root, "long.txt"), Half, "Needle", Half);
      for Case_Sensitive in Boolean loop
         declare
            Found : constant Outcome :=
              Search_For (Root, (if Case_Sensitive then "Needle" else "needle"), Case_Sensitive => Case_Sensitive);
         begin
            Assert (Found.Summary.State = Search.Types.Completed, "the search completed");
            Assert (Natural (Found.Results.Length) = 1, "the 4 MiB line's file is found");
            declare
               Item  : constant Search.Types.Search_Result := Found.Results.First_Element;
               Match : constant Search.Types.Content_Match := Item.Matches.First_Element;
            begin
               Assert (Item.Match_Count = 1, "with its one match");
               Assert (Match.Line = 1 and then Match.First_Byte = Half + 1 and then Match.Last_Byte = Half + 6,
                       "at its place in the line");
               Assert (Length (Match.Preview) <= 3 * Search.Content.Preview_Context + 2 * Ellipsis'Length,
                       "the preview is bounded:" & Natural'Image (Length (Match.Preview)) & " bytes");
               Assert (To_String (Match.Preview) = Ellipsis & Context & "Needle" & Context & Ellipsis,
                       "the preview is the match with its context either side, cut marks at both ends");
            end;
         end;
      end loop;
   end Long_Line;

   procedure Test_Long_Line (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Run_Test is new With_Fixture (Long_Line);
   begin
      Run_Test;
   end Test_Long_Line;

   --  A file over the size limit is not searched and says so; it was read up
   --  to the limit and the rest silently left out.
   procedure Too_Large (Root : String) is
      Big : constant String := Hostkit.Fs.Join (Root, "big.txt");
   begin
      Write_Bytes (Big, "needle" & Repeat ("x", 100));

      declare
         Found : constant Outcome := Search_For (Root, "needle", Max_File_Size => 16);
      begin
         Assert (Found.Results.Is_Empty, "a file over the limit is not searched");
         Assert (Has_Diagnostic (Found.Summary.Diagnostics, "content.file.too_large"),
                 "and the search says the file was too large");
      end;

      declare
         Found : constant Outcome := Search_For (Root, "big", Search.Types.Combined_Mode, Max_File_Size => 16);
      begin
         Assert (Natural (Found.Results.Length) = 1, "a file over the limit is still found by its name");
         Assert (Has_Diagnostic (Found.Results.First_Element.Diagnostics, "content.file.too_large"),
                 "and its result carries the diagnostic");
         Assert (Has_Diagnostic (Found.Summary.Diagnostics, "content.file.too_large"),
                 "as the search's diagnostics do");
      end;

      Assert (Natural (Search_For (Root, "needle", Max_File_Size => 106).Results.Length) = 1,
              "a file exactly at the limit is searched");
   end Too_Large;

   procedure Test_Too_Large (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Run_Test is new With_Fixture (Too_Large);
   begin
      Run_Test;
   end Test_Too_Large;

   --  Whether a file is binary is read from its first 8 KiB: a NUL there,
   --  as grep has it. A NUL later on leaves the file text.
   procedure Binary (Root : String) is
      Nul : constant Character := Byte (0);
   begin
      Write_Bytes (Hostkit.Fs.Join (Root, "early.bin"), "alpha" & Nul & "rest");
      Write_Bytes (Hostkit.Fs.Join (Root, "far.bin"), Repeat ("y", 10) & Nul & Repeat ("y", 100 * 1024) & "gamma");
      Write_Bytes (Hostkit.Fs.Join (Root, "late.txt"),
                   Repeat ("x", Search.Content.Binary_Sniff_Size + 100) & Nul & "beta");

      Assert (Search_For (Root, "alpha").Results.Is_Empty, "a NUL at the start makes a file binary");
      Assert (Search_For (Root, "gamma").Results.Is_Empty,
              "a binary file's text past its first block is not searched either");
      Assert (Natural (Search_For (Root, "beta").Results.Length) = 1,
              "a NUL after the first 8 KiB leaves the file text");
   end Binary;

   procedure Test_Binary (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Run_Test is new With_Fixture (Binary);
   begin
      Run_Test;
   end Test_Binary;

   --  UTF-16 decodes to UTF-8 a code point at a time: every code unit at or
   --  above 128 once became '?', so "é", a CJK character and an emoji were
   --  all unfindable.
   procedure Test_Decode_UTF_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Decoded (UTF_16 (Sample_Units, Big_Endian => False), Big_Endian => False) = Sample_UTF_8,
              "UTF-16LE: the byte order mark is dropped, e-acute, a CJK character and a surrogate pair decode");
      Assert (Decoded (UTF_16 (Sample_Units, Big_Endian => True), Big_Endian => True) = Sample_UTF_8,
              "UTF-16BE decodes alike");
      Assert (Decoded (UTF_16 ([16#D800#, 16#41#], Big_Endian => False), Big_Endian => False) = Replacement & "A",
              "a lead surrogate with no trail becomes U+FFFD and what follows is kept");
      Assert (Decoded (UTF_16 ([16#DC00#], Big_Endian => False), Big_Endian => False) = Replacement,
              "a trail surrogate on its own becomes U+FFFD");
      Assert (Decoded (UTF_16 ([16#D800#], Big_Endian => False), Big_Endian => False) = Replacement,
              "a lead surrogate at the end becomes U+FFFD");
      Assert (Decoded (UTF_16 ([16#41#], Big_Endian => False) & "B", Big_Endian => False) = "A" & Replacement,
              "an odd byte at the end becomes U+FFFD");
      Assert (Decoded (UTF_16 ([16#0A#, 16#09#, 16#0D#], Big_Endian => False), Big_Endian => False)
                = String'[ASCII.LF, ASCII.HT, ASCII.CR],
              "control characters pass through");
      Assert (Decoded ("", Big_Endian => False) = "", "nothing decodes to nothing");
   end Test_Decode_UTF_16;

   procedure UTF_16_Files (Root : String) is
   begin
      Write_Bytes (Hostkit.Fs.Join (Root, "le.txt"), UTF_16 (Sample_Units, Big_Endian => False));
      Write_Bytes (Hostkit.Fs.Join (Root, "be.txt"), UTF_16 (Sample_Units, Big_Endian => True));

      Assert (Natural (Search_For (Root, E_Acute).Results.Length) = 2, "e-acute is found in UTF-16LE and BE");
      Assert (Natural (Search_For (Root, Zhong).Results.Length) = 2, "a CJK character is found in both");
      Assert (Natural (Search_For (Root, Grin).Results.Length) = 2, "a surrogate pair's character is found in both");
      declare
         Found : constant Outcome := Search_For (Root, "end");
      begin
         Assert (Natural (Found.Results.Length) = 2, "ASCII text is found in both");
         for Item of Found.Results loop
            Assert (To_String (Item.Matches.First_Element.Preview) = Sample_UTF_8,
                    "the preview is the decoded line");
         end loop;
      end;
   end UTF_16_Files;

   procedure Test_UTF_16_Files (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Run_Test is new With_Fixture (UTF_16_Files);
   begin
      Run_Test;
   end Test_UTF_16_Files;

   procedure Test_Preview_Window (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Search.Content;
      Wide : constant String := Repeat (Zhong, 200);  --  600 bytes
      Line : constant String := Wide & "needle" & Wide;
      Long : constant String := Repeat ("a", 1000);
   begin
      Assert (Preview_Of ("a needle here", 3, 8) = "a needle here", "a short line is its own preview");
      Assert (Preview_Of ("abc", 4, 3) = "abc", "an empty match at the end of a short line");
      --  The match is bytes 601 .. 606. 200 bytes before it is byte 401, the
      --  middle of a character: the start moves on to 403. 200 bytes after it
      --  is byte 806, inside one: the end moves back to 804.
      Assert (Preview_Of (Line, 601, 606) = Ellipsis & Repeat (Zhong, 66) & "needle" & Repeat (Zhong, 66) & Ellipsis,
              "the cuts fall between UTF-8 sequences, each marked");
      Assert (Preview_Of (Long, 1, 1000) = Long (1 .. 2 * Preview_Context) & Ellipsis,
              "a long match shows its first part and the context after that");
      Assert (Preview_Of (Long, 1000, 1000) = Ellipsis & Long (800 .. 1000),
              "a match at the end of a long line is cut only before");
   end Test_Preview_Window;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Long_Line'Access, "a 4 MiB line is searched and its preview is bounded");
      Register_Routine (T, Test_Too_Large'Access, "a file over the size limit is reported, not cut");
      Register_Routine (T, Test_Binary'Access, "binary is decided by a NUL in the first 8 KiB");
      Register_Routine (T, Test_Decode_UTF_16'Access, "UTF-16 decodes to UTF-8 with surrogate pairs");
      Register_Routine (T, Test_UTF_16_Files'Access, "UTF-16 files are searched as their decoded text");
      Register_Routine (T, Test_Preview_Window'Access, "a preview is a window cut at UTF-8 boundaries");
   end Register_Tests;
end Search_Tests.Content_Tests;

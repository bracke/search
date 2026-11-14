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

   --  One result with this path and name, for the escaping cases.
   function One (Path : String; Name : String; Id : Natural := 7; Matches : Natural := 12)
     return Search.Types.Result_Vectors.Vector
   is
      Results : Search.Types.Result_Vectors.Vector;
   begin
      Results.Append
        (Search.Types.Search_Result'
           (Id           => Id,
            Root         => To_Unbounded_String ("/r"),
            Path         => To_Unbounded_String (Path),
            Name         => To_Unbounded_String (Name),
            Size         => 1,
            Is_Directory => False,
            Match_Count  => Matches,
            Matches      => <>,
            Freshness    => Search.Types.Fresh,
            Revision     => 1,
            Diagnostics  => <>));
      return Results;
   end One;

   Replacement : constant String := Character'Val (16#EF#) & Character'Val (16#BF#) & Character'Val (16#BD#);
   E_Acute     : constant String := Character'Val (16#C3#) & Character'Val (16#A9#);

   procedure Test_JSON_Escapes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Got : constant String :=
        Search.Exports.Render
          (One ("/r/a" & ASCII.LF & "b" & ASCII.HT & Character'Val (1) & """\" & Character'Val (16#1F#),
                "caf" & E_Acute & Character'Val (16#FF#) & "x" & Character'Val (16#C3#)),
           Search.Types.Export_JSON);
      Wanted : constant String :=
        "[{""id"":7,""path"":""/r/a\u000Ab\u0009\u0001\""\\\u001F"",""name"":""caf" & E_Acute & Replacement
        & "x" & Replacement & """,""matches"":12}]";
   begin
      Assert (Got = Wanted, "JSON escapes control characters as \u00XX and replaces bad UTF-8: " & Got);
      Assert (Search.Exports.Render
                (One ("/r/" & Character'Val (16#ED#) & Character'Val (16#A0#) & Character'Val (16#80#), "n"),
                 Search.Types.Export_JSON)
              = "[{""id"":7,""path"":""/r/" & Replacement & Replacement & Replacement
                & """,""name"":""n"",""matches"":12}]",
              "an encoded surrogate is not UTF-8 either");
   end Test_JSON_Escapes;

   procedure Test_CSV_Numbers (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Got : constant String :=
        Search.Exports.Render (One ("/r/a,""b""" & ASCII.LF & "c", "a"), Search.Types.Export_CSV);
   begin
      Assert (Got = "id,path,name,matches" & ASCII.LF
                & "7,""/r/a,""""b""""" & ASCII.LF & "c"",""a"",12" & ASCII.LF,
              "CSV numbers have no leading space, and text fields are quoted: " & Got);
   end Test_CSV_Numbers;

   procedure Test_Text_Lines (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Search.Exports.Render (One ("/r/plain name", "plain name"), Search.Types.Export_Text)
              = "/r/plain name [12]" & ASCII.LF,
              "a plain path is written as it is, the count without a leading space");
      Assert (Search.Exports.Render (One ("C:\dir\new", "new"), Search.Types.Export_Text)
              = "C:\dir\new [12]" & ASCII.LF,
              "a Windows path keeps its backslashes");
      Assert (Search.Exports.Render
                (One ("/r/two" & ASCII.LF & "lines\" & ASCII.HT & """" & Character'Val (16#7F#), "x"),
                 Search.Types.Export_Text)
              = """/r/two\nlines\\\t\""\x7F"" [12]" & ASCII.LF,
              "a path with a control character is quoted and escaped, one line still one result");
      Assert (Search.Exports.Render (One ("""quoted", "x"), Search.Types.Export_Text)
              = """\""quoted"" [12]" & ASCII.LF,
              "a path starting with a quote is quoted, so it cannot be read as an escaped one");
   end Test_Text_Lines;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Formats'Access, "structured formats");
      Register_Routine (T, Test_JSON_Escapes'Access, "JSON escapes control characters and invalid UTF-8");
      Register_Routine (T, Test_CSV_Numbers'Access, "CSV numbers have no leading space");
      Register_Routine (T, Test_Text_Lines'Access, "text output keeps one result to a line");
   end Register_Tests;
end Search_Tests.Export_Tests;

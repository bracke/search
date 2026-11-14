with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;

with Search.Text_Fold;

package body Search.Content is
   use type Search.Types.Encoding_Kind;
   use type Search.Types.Text_Mode;
   use type Regexp.Match_Status;

   --  A file's bytes, its decoded text and its folded text live on the heap:
   --  a String the size of a file -- or of one long line -- on the stack of
   --  the task that walks the tree overflowed it, and that file's matches
   --  were lost with a Storage_Error.
   type Text_Access is access String;
   procedure Free is new Ada.Unchecked_Deallocation (String, Text_Access);

   --  How much is read from the file at a time.
   Block_Size : constant := 64 * 1024;

   --  The largest file that is read whatever the query allows: a String is
   --  indexed by Natural, and UTF-16 decodes to half as much again.
   Max_Readable : constant Long_Long_Integer := Long_Long_Integer (Natural'Last / 2);

   --  U+2026 HORIZONTAL ELLIPSIS, marking where a preview cuts its line.
   Ellipsis : constant String := [Character'Val (16#E2#), Character'Val (16#80#), Character'Val (16#A6#)];

   --  U+FFFD REPLACEMENT CHARACTER, for what UTF-16 decoding cannot read.
   Replacement : constant Natural := 16#FFFD#;

   function Is_Continuation (Ch : Character) return Boolean is (Character'Pos (Ch) in 16#80# .. 16#BF#);

   function Preview_Of (Line : String; First : Positive; Last : Natural) return String is
      Length    : constant Natural := Line'Length;
      --  The end of the part of the match shown: all of it, or its first
      --  Preview_Context bytes.
      Match_End : constant Natural := Natural'Min (Natural'Max (Last, First - 1), First + Preview_Context - 1);
      Start     : Positive := (if First > Preview_Context then First - Preview_Context else 1);
      Stop      : Natural := Natural'Min (Length, Match_End + Preview_Context);

      function At_Offset (Offset : Positive) return Character is (Line (Line'First + Offset - 1));
   begin
      if Start > Length + 1 then
         Start := Length + 1;
      end if;
      --  Neither cut splits a UTF-8 sequence: the start moves forward past
      --  continuation bytes, the end back before a sequence it would split.
      --  A sequence is at most 4 bytes, so 3 steps reach its edge -- and a
      --  text that is not UTF-8 is not walked far looking for one.
      for Step in 1 .. 3 loop
         exit when Start = 1 or else Start > Length or else not Is_Continuation (At_Offset (Start));
         Start := Start + 1;
      end loop;
      for Step in 1 .. 3 loop
         exit when Stop >= Length or else Stop < Start or else not Is_Continuation (At_Offset (Stop + 1));
         Stop := Stop - 1;
      end loop;

      return (if Start > 1 then Ellipsis else "")
        & Line (Line'First + Start - 1 .. Line'First + Stop - 1)
        & (if Stop < Length then Ellipsis else "");
   end Preview_Of;

   procedure Decode_UTF_16
     (Text       : String;
      Big_Endian : Boolean;
      Into       : out String;
      Last       : out Natural)
   is
      I : Integer := Text'First;

      --  The code unit at Text (At_Index .. At_Index + 1).
      function Unit (At_Index : Positive) return Natural is
        (if Big_Endian
         then Character'Pos (Text (At_Index)) * 256 + Character'Pos (Text (At_Index + 1))
         else Character'Pos (Text (At_Index + 1)) * 256 + Character'Pos (Text (At_Index)));

      procedure Put (Code : Natural) is
         procedure Put_Byte (Value : Natural) is
         begin
            Last := Last + 1;
            Into (Last) := Character'Val (Value);
         end Put_Byte;
      begin
         if Code < 16#80# then
            Put_Byte (Code);
         elsif Code < 16#800# then
            Put_Byte (16#C0# + Code / 16#40#);
            Put_Byte (16#80# + Code mod 16#40#);
         elsif Code < 16#1_0000# then
            Put_Byte (16#E0# + Code / 16#1000#);
            Put_Byte (16#80# + (Code / 16#40#) mod 16#40#);
            Put_Byte (16#80# + Code mod 16#40#);
         else
            Put_Byte (16#F0# + Code / 16#4_0000#);
            Put_Byte (16#80# + (Code / 16#1000#) mod 16#40#);
            Put_Byte (16#80# + (Code / 16#40#) mod 16#40#);
            Put_Byte (16#80# + Code mod 16#40#);
         end if;
      end Put;
   begin
      Last := Into'First - 1;

      if Text'Length >= 2 and then Unit (Text'First) = 16#FEFF# then
         I := Text'First + 2;
      end if;

      while I < Text'Last loop
         declare
            High : constant Natural := Unit (I);
         begin
            if High in 16#D800# .. 16#DBFF# then
               --  A lead surrogate: with a trail surrogate after it, the two
               --  are one supplementary code point.
               if I + 3 <= Text'Last and then Unit (I + 2) in 16#DC00# .. 16#DFFF# then
                  Put (16#1_0000# + (High - 16#D800#) * 16#400# + (Unit (I + 2) - 16#DC00#));
                  I := I + 4;
               else
                  Put (Replacement);
                  I := I + 2;
               end if;
            elsif High in 16#DC00# .. 16#DFFF# then
               Put (Replacement);  --  a trail surrogate with no lead before it
               I := I + 2;
            else
               Put (High);
               I := I + 2;
            end if;
         end;
      end loop;

      if I = Text'Last then
         Put (Replacement);  --  half a code unit
      end if;
   end Decode_UTF_16;

   --  Whether the opening bytes of a file say it is binary: a NUL among its
   --  first Binary_Sniff_Size bytes, unless it opens with a UTF-16 byte order
   --  mark (UTF-16 text is full of NULs).
   function Looks_Binary (Head : String) return Boolean is
      Sniff_Last : constant Natural :=
        (if Head'Length > Binary_Sniff_Size then Head'First + Binary_Sniff_Size - 1 else Head'Last);
   begin
      if Head'Length >= 2
        and then ((Character'Pos (Head (Head'First)) = 16#FF# and then Character'Pos (Head (Head'First + 1)) = 16#FE#)
                  or else (Character'Pos (Head (Head'First)) = 16#FE#
                           and then Character'Pos (Head (Head'First + 1)) = 16#FF#))
      then
         return False;
      end if;
      return Ada.Strings.Fixed.Index (Head (Head'First .. Sniff_Last), [1 => Character'Val (0)]) > 0;
   end Looks_Binary;

   --  Read the file at Path into Into, a block at a time, until Into is full
   --  or the file ends. Reading stops after the first block when that block
   --  shows the file is binary.
   procedure Read_Text
     (Path   : String;
      Into   : out String;
      Last   : out Natural;
      Binary : out Boolean)
   is
      use Ada.Streams;
      File  : Stream_IO.File_Type;
      Block : Stream_Element_Array (1 .. Block_Size);
      Got   : Stream_Element_Offset;
   begin
      Last := Into'First - 1;
      Binary := False;
      Stream_IO.Open (File, Stream_IO.In_File, Path, Form => "shared=no");
      while Last < Into'Last and then not Stream_IO.End_Of_File (File) loop
         Stream_IO.Read (File, Block (1 .. Stream_Element_Offset (Natural'Min (Block_Size, Into'Last - Last))), Got);
         exit when Got < 1;
         for Index in 1 .. Got loop
            Into (Last + Natural (Index)) := Character'Val (Block (Index));
         end loop;
         --  The first block decides: a binary file is not read further.
         if Last < Into'First then
            Last := Last + Natural (Got);
            Binary := Looks_Binary (Into (Into'First .. Last));
            exit when Binary;
         else
            Last := Last + Natural (Got);
         end if;
      end loop;
      Stream_IO.Close (File);
   exception
      when others =>
         if Stream_IO.Is_Open (File) then
            Stream_IO.Close (File);
         end if;
         raise;
   end Read_Text;

   --  A text's encoding by its byte order mark, or else whether it is UTF-8.
   function Detect_Encoding (Text : String) return Search.Types.Encoding_Kind is
   begin
      if Text'Length >= 2 then
         if Character'Pos (Text (Text'First)) = 16#FF#
           and then Character'Pos (Text (Text'First + 1)) = 16#FE#
         then
            return Search.Types.Encoding_UTF_16_LE;
         elsif Character'Pos (Text (Text'First)) = 16#FE#
           and then Character'Pos (Text (Text'First + 1)) = 16#FF#
         then
            return Search.Types.Encoding_UTF_16_BE;
         end if;
      end if;

      if Regexp.Validate_UTF_8 (Text).Valid then
         return Search.Types.Encoding_UTF_8;
      else
         return Search.Types.Encoding_Unknown;
      end if;
   end Detect_Encoding;

   --  Find the matches in one line.
   --
   --  @param Line The line, a slice of the file's text.
   --  @param Hay The same slice of the text as a literal match compares it
   --         (folded when the query ignores case; Line itself otherwise).
   procedure Append_Line_Matches
     (Result : in out Scan_Result;
      Line   : String;
      Hay    : String;
      Number : Positive;
      Query  : Search.Queries.Query;
      Needle : String;
      Regex  : Regexp.Compile_Result)
   is
      From  : Positive := 1;
      Found : Regexp.Match_Result;
      Index : Natural;

      --  Record the match at First .. Last, counted from 1 at Line'First.
      procedure Add (First : Positive; Last : Natural) is
      begin
         Result.Match_Count := Result.Match_Count + 1;
         Result.Matches.Append
           (Search.Types.Content_Match'
              (Line       => Number,
               Column     => First,
               First_Byte => First,
               Last_Byte  => Last,
               Preview    => To_Unbounded_String (Preview_Of (Line, First, Last))));
      end Add;
   begin
      if Search.Queries.Text_Mode (Query) = Search.Types.Regular_Expression then
         loop
            Found := Regexp.Find_From_Planned
              (Regex.Expression,
               Line,
               From,
               (Case_Sensitive => Search.Queries.Case_Sensitive (Query),
                Character_Mode => Regexp.UTF_8_Mode,
                others         => <>));
            exit when Found.Status /= Regexp.Match_Ok;
            Add (Positive'Max (1, Found.First), Found.Last);
            exit when Found.Last + 1 > Line'Length;
            From := Positive'Max (Found.Last + 1, Found.First + 1);
         end loop;
      else
         --  Index answers a position in Hay itself, also over a slice of it.
         Index := Ada.Strings.Fixed.Index (Hay, Needle);
         while Index > 0 loop
            Add (Index - Hay'First + 1, Index - Hay'First + Needle'Length);
            exit when Index + Needle'Length > Hay'Last;
            Index := Ada.Strings.Fixed.Index (Hay (Index + Needle'Length .. Hay'Last), Needle);
         end loop;
      end if;
   end Append_Line_Matches;

   function Scan_File
     (Path   : String;
      Query  : Search.Queries.Query;
      Needle : String;
      Regex  : Regexp.Compile_Result) return Scan_Result
   is
      Result    : Scan_Result;
      Size      : Long_Long_Integer;
      Raw       : Text_Access;
      Raw_Last  : Natural := 0;
      --  The text searched: Raw itself, or what UTF-16 decodes to.
      Text      : Text_Access;
      Text_Last : Natural := 0;
      --  The text as a literal match compares it: Text, or Text folded.
      Hay       : Text_Access;
      Binary    : Boolean := False;

      procedure Note (Code : String) is
      begin
         Result.Diagnostics.Append
           (Search.Types.Diagnostic'
              (Severity => Search.Types.Warning,
               Code     => To_Unbounded_String (Code),
               Path     => To_Unbounded_String (Path),
               Message  => To_Unbounded_String (Code)));
      end Note;

      procedure Release is
      begin
         if Hay = Text then
            Hay := null;
         else
            Free (Hay);
         end if;
         if Text = Raw then
            Text := null;
         else
            Free (Text);
         end if;
         Free (Raw);
      end Release;
   begin
      --  The size first: a file over the limit is not read at all. It was
      --  read up to the limit and the rest silently left unsearched.
      begin
         Size := Long_Long_Integer (Ada.Directories.Size (Path));
      exception
         when others =>
            Note ("content.file.missing");
            return Result;
      end;
      if Size > Search.Queries.Max_File_Size (Query) or else Size > Max_Readable then
         Note ("content.file.too_large");
         return Result;
      end if;

      begin
         Raw := new String (1 .. Natural (Size));
         Read_Text (Path, Raw.all, Raw_Last, Binary);
      exception
         when others =>
            Release;
            Note ("content.file.unreadable");
            return Result;
      end;

      if Binary then
         Result.Encoding := Search.Types.Encoding_Binary;
         Result.Binary := True;
         Release;
         return Result;
      end if;

      Result.Encoding := Detect_Encoding (Raw (1 .. Raw_Last));
      if Result.Encoding in Search.Types.Encoding_UTF_16_LE | Search.Types.Encoding_UTF_16_BE then
         Text := new String (1 .. UTF_8_Capacity (Raw_Last));
         Decode_UTF_16
           (Raw (1 .. Raw_Last),
            Big_Endian => Result.Encoding = Search.Types.Encoding_UTF_16_BE,
            Into       => Text.all,
            Last       => Text_Last);
         Free (Raw);
      else
         Text := Raw;
         Text_Last := Raw_Last;
      end if;

      --  Folded once, for the whole file, where a literal match ignores case;
      --  folding keeps every byte where it was, so a position in Hay is the
      --  same position in Text.
      if Search.Queries.Text_Mode (Query) = Search.Types.Literal_Text
        and then not Search.Queries.Case_Sensitive (Query)
      then
         Hay := new String (1 .. Text_Last);
         Hay.all := Text (1 .. Text_Last);
         Search.Text_Fold.Fold_In_Place (Hay.all);
      else
         Hay := Text;
      end if;

      declare
         Start   : Positive := 1;
         Stop    : Natural;
         Line_No : Positive := 1;
      begin
         while Start <= Text_Last loop
            --  Index over a slice returns an absolute position in Text, so it
            --  is the line terminator's index directly.
            Stop := Ada.Strings.Fixed.Index (Text (Start .. Text_Last), [1 => ASCII.LF]);
            if Stop = 0 then
               Stop := Text_Last + 1;
            end if;
            Append_Line_Matches
              (Result, Text (Start .. Stop - 1), Hay (Start .. Stop - 1), Line_No, Query, Needle, Regex);
            Start := Stop + 1;
            Line_No := Line_No + 1;
         end loop;
      end;

      Release;
      return Result;
   exception
      when others =>
         Release;
         raise;
   end Scan_File;
end Search.Content;

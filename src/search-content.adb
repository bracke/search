with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Sequential_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Regexp;

package body Search.Content is
   use type Search.Types.Encoding_Kind;
   use type Search.Types.Text_Mode;
   use type Regexp.Match_Status;

   package Byte_IO is new Ada.Sequential_IO (Character);

   function Lower (Text : String) return String is
      Result : String (Text'Range);
   begin
      for I in Text'Range loop
         Result (I) := Ada.Characters.Handling.To_Lower (Text (I));
      end loop;
      return Result;
   end Lower;

   function Contains_Nul (Text : String) return Boolean is
   begin
      for Ch of Text loop
         if Ch = Character'Val (0) then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Nul;

   function Decode_UTF_16 (Text : String; Big_Endian : Boolean) return Unbounded_String is
      Result : Unbounded_String;
      First  : Positive := Text'First;
      Code   : Natural;
   begin
      if Text'Length >= 2 then
         declare
            A : constant Natural := Character'Pos (Text (Text'First));
            B : constant Natural := Character'Pos (Text (Text'First + 1));
         begin
            if (A = 16#FF# and then B = 16#FE#) or else (A = 16#FE# and then B = 16#FF#) then
               First := Text'First + 2;
            end if;
         end;
      end if;

      for I in First .. Text'Last - 1 loop
         if (I - First) mod 2 = 0 then
            if Big_Endian then
               Code := Character'Pos (Text (I)) * 256 + Character'Pos (Text (I + 1));
            else
               Code := Character'Pos (Text (I + 1)) * 256 + Character'Pos (Text (I));
            end if;

            if Code in 1 .. 127 then
               Append (Result, Character'Val (Code));
            elsif Code = 10 or else Code = 13 or else Code = 9 then
               Append (Result, Character'Val (Code));
            else
               Append (Result, '?');
            end if;
         end if;
      end loop;

      return Result;
   end Decode_UTF_16;

   function Read_Bounded (Path : String; Max_Bytes : Long_Long_Integer) return Unbounded_String is
      File   : Byte_IO.File_Type;
      Result : Unbounded_String;
      Ch     : Character;
      Count  : Long_Long_Integer := 0;
   begin
      Byte_IO.Open (File, Byte_IO.In_File, Path);
      while not Byte_IO.End_Of_File (File) and then Count < Max_Bytes loop
         Byte_IO.Read (File, Ch);
         Append (Result, Ch);
         Count := Count + 1;
      end loop;
      Byte_IO.Close (File);
      return Result;
   exception
      when others =>
         if Byte_IO.Is_Open (File) then
            Byte_IO.Close (File);
         end if;
         return Null_Unbounded_String;
   end Read_Bounded;

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

      if Contains_Nul (Text) then
         return Search.Types.Encoding_Binary;
      elsif Regexp.Validate_UTF_8 (Text).Valid then
         return Search.Types.Encoding_UTF_8;
      else
         return Search.Types.Encoding_Unknown;
      end if;
   end Detect_Encoding;

   procedure Append_Line_Matches
     (Result : in out Scan_Result;
      Line   : String;
      Number : Positive;
      Query  : Search.Queries.Query;
      Regex  : Regexp.Compile_Result)
   is
      Pattern : constant String := Search.Queries.Pattern (Query);
      Hay     : constant String := (if Search.Queries.Case_Sensitive (Query) then Line else Lower (Line));
      Needle  : constant String := (if Search.Queries.Case_Sensitive (Query) then Pattern else Lower (Pattern));
      From    : Positive := 1;
      Found   : Regexp.Match_Result;
      Index   : Natural;
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
            Result.Match_Count := Result.Match_Count + 1;
            Result.Matches.Append
              (Search.Types.Content_Match'
                 (Line       => Number,
                  Column     => Positive'Max (1, Found.First),
                  First_Byte => Found.First,
                  Last_Byte  => Found.Last,
                  Preview    => To_Unbounded_String (Line)));
            exit when Found.Last + 1 > Line'Length;
            From := Positive'Max (Found.Last + 1, Found.First + 1);
         end loop;
      else
         Index := Ada.Strings.Fixed.Index (Hay, Needle);
         while Index > 0 loop
            Result.Match_Count := Result.Match_Count + 1;
            Result.Matches.Append
              (Search.Types.Content_Match'
                 (Line       => Number,
                  Column     => Positive'Max (1, Index),
                  First_Byte => Index,
                  Last_Byte  => Index + Needle'Length - 1,
                  Preview    => To_Unbounded_String (Line)));
            exit when Index + Needle'Length > Hay'Length;
            Index := Ada.Strings.Fixed.Index (Hay (Index + Needle'Length .. Hay'Last), Needle);
            if Index > 0 then
               Index := Index + Needle'Length;
            end if;
         end loop;
      end if;
   end Append_Line_Matches;

   function Scan_File
     (Path  : String;
      Query : Search.Queries.Query) return Scan_Result
   is
      Result   : Scan_Result;
      Raw      : constant String := To_String (Read_Bounded (Path, Search.Queries.Max_File_Size (Query)));
      Text     : Unbounded_String;
      Regex    : Regexp.Compile_Result;
      Start    : Positive := 1;
      Stop     : Natural;
      Line_No  : Positive := 1;
   begin
      if not Ada.Directories.Exists (Path) then
         Result.Diagnostics.Append
           (Search.Types.Diagnostic'
              (Severity => Search.Types.Warning,
               Code     => To_Unbounded_String ("content.file.missing"),
               Path     => To_Unbounded_String (Path),
               Message  => To_Unbounded_String ("content.file.missing")));
         return Result;
      end if;

      Result.Encoding := Detect_Encoding (Raw);
      Result.Binary := Result.Encoding = Search.Types.Encoding_Binary;
      if Result.Binary then
         return Result;
      elsif Result.Encoding = Search.Types.Encoding_UTF_16_LE then
         Text := Decode_UTF_16 (Raw, Big_Endian => False);
      elsif Result.Encoding = Search.Types.Encoding_UTF_16_BE then
         Text := Decode_UTF_16 (Raw, Big_Endian => True);
      else
         Text := To_Unbounded_String (Raw);
      end if;

      if Search.Queries.Text_Mode (Query) = Search.Types.Regular_Expression then
         Regex := Regexp.Compile (Search.Queries.Pattern (Query));
      end if;

      declare
         S : constant String := To_String (Text);
      begin
         while Start <= S'Length loop
            --  Index over a slice returns an absolute position in S, so it is the
            --  line terminator's index directly -- no Start-relative adjustment.
            Stop := Ada.Strings.Fixed.Index (S (Start .. S'Last), "" & ASCII.LF);
            if Stop = 0 then
               Stop := S'Last + 1;
            end if;
            Append_Line_Matches (Result, S (Start .. Stop - 1), Line_No, Query, Regex);
            Start := Stop + 1;
            Line_No := Line_No + 1;
         end loop;
      end;

      return Result;
   end Scan_File;
end Search.Content;

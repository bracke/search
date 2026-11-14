with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Search.Exports is

   Hex_Digits : constant String := "0123456789ABCDEF";

   --  Value written as decimal digits, without the sign column 'Image adds.
   function Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Left));

   --  Two upper-case hexadecimal digits for Ch.
   function Hex (Ch : Character) return String is
     [Hex_Digits (Character'Pos (Ch) / 16 + 1), Hex_Digits (Character'Pos (Ch) mod 16 + 1)];

   --  How many bytes the well-formed UTF-8 sequence at Index in Text takes,
   --  or 0 when the bytes there are not one: a stray continuation byte, a
   --  lead byte without its continuations, an overlong form, a surrogate,
   --  or a code point past U+10FFFF.
   function Sequence_Length (Text : String; Index : Positive) return Natural is
      Lead : constant Natural := Character'Pos (Text (Index));

      function Continuation (At_Index : Positive) return Natural is
        (if At_Index <= Text'Last and then Character'Pos (Text (At_Index)) in 16#80# .. 16#BF#
         then Character'Pos (Text (At_Index)) else 16#100#);

      Second : Natural;
   begin
      if Lead < 16#80# then
         return 1;
      elsif Lead in 16#C2# .. 16#DF# then
         return (if Continuation (Index + 1) < 16#100# then 2 else 0);
      elsif Lead in 16#E0# .. 16#EF# then
         Second := Continuation (Index + 1);
         if Second = 16#100#
           or else (Lead = 16#E0# and then Second < 16#A0#)    --  overlong
           or else (Lead = 16#ED# and then Second > 16#9F#)    --  a surrogate
           or else Continuation (Index + 2) = 16#100#
         then
            return 0;
         end if;
         return 3;
      elsif Lead in 16#F0# .. 16#F4# then
         Second := Continuation (Index + 1);
         if Second = 16#100#
           or else (Lead = 16#F0# and then Second < 16#90#)    --  overlong
           or else (Lead = 16#F4# and then Second > 16#8F#)    --  past U+10FFFF
           or else Continuation (Index + 2) = 16#100#
           or else Continuation (Index + 3) = 16#100#
         then
            return 0;
         end if;
         return 4;
      end if;
      return 0;
   end Sequence_Length;

   --  U+FFFD REPLACEMENT CHARACTER, in UTF-8.
   Replacement : constant String :=
     [Character'Val (16#EF#), Character'Val (16#BF#), Character'Val (16#BD#)];

   --  Text as a JSON string's contents. JSON is UTF-8 text: a quote, a
   --  backslash and every control character below U+0020 are escaped
   --  (\", \\, \u00XX), and a byte that is not part of well-formed UTF-8 --
   --  a POSIX name may hold any bytes -- becomes U+FFFD, so what is written
   --  always parses.
   function Escape_JSON (Text : String) return String is
      Result : Unbounded_String;
      Index  : Positive := Text'First;
      Width  : Natural;
   begin
      while Index <= Text'Last loop
         Width := Sequence_Length (Text, Index);
         if Width = 0 then
            Append (Result, Replacement);
            Index := Index + 1;
         elsif Width > 1 then
            Append (Result, Text (Index .. Index + Width - 1));
            Index := Index + Width;
         else
            case Text (Index) is
               when '"' =>
                  Append (Result, "\""");
               when '\' =>
                  Append (Result, "\\");
               when Character'Val (0) .. Character'Val (16#1F#) =>
                  Append (Result, "\u00" & Hex (Text (Index)));
               when others =>
                  Append (Result, Text (Index));
            end case;
            Index := Index + 1;
         end if;
      end loop;
      return To_String (Result);
   end Escape_JSON;

   --  Text as a quoted CSV field (RFC 4180): a quote is doubled, and a line
   --  break inside the quotes is part of the field.
   function Escape_CSV (Text : String) return String is
      Result : Unbounded_String := To_Unbounded_String ("""");
   begin
      for Ch of Text loop
         if Ch = '"' then
            Append (Result, """""");
         else
            Append (Result, Ch);
         end if;
      end loop;
      Append (Result, """");
      return To_String (Result);
   end Escape_CSV;

   --  A path as a line of the text format. A path holding a control
   --  character -- a line break in a POSIX name would otherwise split one
   --  result over two lines -- or starting with a double quote is written
   --  between double quotes, C-style: \n, \r, \t, \" and \\, and \xHH for
   --  any other control byte. Every other path is written as it is, so a
   --  Windows path keeps its backslashes.
   function Escape_Text (Text : String) return String is
      Needs_Quotes : constant Boolean :=
        (Text'Length > 0 and then Text (Text'First) = '"')
        or else (for some Ch of Text => Ch < ' ' or else Ch = Character'Val (16#7F#));
      Result       : Unbounded_String := To_Unbounded_String ("""");
   begin
      if not Needs_Quotes then
         return Text;
      end if;
      for Ch of Text loop
         case Ch is
            when ASCII.LF =>
               Append (Result, "\n");
            when ASCII.CR =>
               Append (Result, "\r");
            when ASCII.HT =>
               Append (Result, "\t");
            when '"' =>
               Append (Result, "\""");
            when '\' =>
               Append (Result, "\\");
            when Character'Val (0) .. Character'Val (8) | Character'Val (11) .. Character'Val (12)
              | Character'Val (14) .. Character'Val (16#1F#) | Character'Val (16#7F#) =>
               Append (Result, "\x" & Hex (Ch));
            when others =>
               Append (Result, Ch);
         end case;
      end loop;
      Append (Result, """");
      return To_String (Result);
   end Escape_Text;

   function Render_JSON (Results : Search.Types.Result_Vectors.Vector) return String is
      Output : Unbounded_String := To_Unbounded_String ("[");
      First  : Boolean := True;
   begin
      for Result of Results loop
         if not First then
            Append (Output, ",");
         end if;
         First := False;
         Append
           (Output,
            "{""id"":" & Image (Result.Id) &
            ",""path"":""" & Escape_JSON (To_String (Result.Path)) &
            """,""name"":""" & Escape_JSON (To_String (Result.Name)) &
            """,""matches"":" & Image (Result.Match_Count) & "}");
      end loop;
      Append (Output, "]");
      return To_String (Output);
   end Render_JSON;

   function Render_CSV (Results : Search.Types.Result_Vectors.Vector) return String is
      Output : Unbounded_String := To_Unbounded_String ("id,path,name,matches" & ASCII.LF);
   begin
      for Result of Results loop
         Append
           (Output,
            Image (Result.Id) & "," &
            Escape_CSV (To_String (Result.Path)) & "," &
            Escape_CSV (To_String (Result.Name)) & "," &
            Image (Result.Match_Count) & ASCII.LF);
      end loop;
      return To_String (Output);
   end Render_CSV;

   function Render_Text (Results : Search.Types.Result_Vectors.Vector) return String is
      Output : Unbounded_String;
   begin
      for Result of Results loop
         Append
           (Output,
            Escape_Text (To_String (Result.Path)) & " [" & Image (Result.Match_Count) & "]" & ASCII.LF);
      end loop;
      return To_String (Output);
   end Render_Text;

   function Render
     (Results : Search.Types.Result_Vectors.Vector;
      Format  : Search.Types.Export_Format) return String is
   begin
      case Format is
         when Search.Types.Export_JSON =>
            return Render_JSON (Results);
         when Search.Types.Export_CSV =>
            return Render_CSV (Results);
         when Search.Types.Export_Text =>
            return Render_Text (Results);
      end case;
   end Render;
end Search.Exports;

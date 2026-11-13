with Ada.Wide_Wide_Characters.Handling;

package body Search.Text_Fold is

   subtype Byte is Natural range 0 .. 255;

   function At_Byte (Text : String; Index : Positive) return Byte is
     (Character'Pos (Text (Index)));

   --  The UTF-8 bytes of Code (which the caller has checked is a scalar value).
   function Encode (Code : Natural) return String is
      function Char (Value : Natural) return Character is (Character'Val (Value));
   begin
      if Code < 16#80# then
         return [1 => Char (Code)];
      elsif Code < 16#800# then
         return [Char (16#C0# + Code / 16#40#), Char (16#80# + Code mod 16#40#)];
      elsif Code < 16#1_0000# then
         return [Char (16#E0# + Code / 16#1000#),
                 Char (16#80# + (Code / 16#40#) mod 16#40#),
                 Char (16#80# + Code mod 16#40#)];
      else
         return [Char (16#F0# + Code / 16#4_0000#),
                 Char (16#80# + (Code / 16#1000#) mod 16#40#),
                 Char (16#80# + (Code / 16#40#) mod 16#40#),
                 Char (16#80# + Code mod 16#40#)];
      end if;
   end Encode;

   --  Decode the well-formed UTF-8 sequence at Text (Index), as RFC 3629 has
   --  it (no overlong forms, no surrogates, nothing past U+10FFFF). Length is
   --  0 when there is none there.
   procedure Decode
     (Text   : String;
      Index  : Positive;
      Code   : out Natural;
      Length : out Natural)
   is
      Lead : constant Byte := At_Byte (Text, Index);
      Low  : Byte := 16#80#;  --  the range of the second byte, by lead byte
      High : Byte := 16#BF#;
   begin
      Code   := 0;
      Length := 0;
      case Lead is
         when 16#C2# .. 16#DF# =>
            Length := 2;
            Code := Lead - 16#C0#;
         when 16#E0# .. 16#EF# =>
            Length := 3;
            Code := Lead - 16#E0#;
            if Lead = 16#E0# then
               Low := 16#A0#;
            elsif Lead = 16#ED# then
               High := 16#9F#;
            end if;
         when 16#F0# .. 16#F4# =>
            Length := 4;
            Code := Lead - 16#F0#;
            if Lead = 16#F0# then
               Low := 16#90#;
            elsif Lead = 16#F4# then
               High := 16#8F#;
            end if;
         when others =>
            return;
      end case;

      if Index + Length - 1 > Text'Last then
         Length := 0;
         return;
      end if;

      for Offset in 1 .. Length - 1 loop
         declare
            Next  : constant Byte := At_Byte (Text, Index + Offset);
            First : constant Byte := (if Offset = 1 then Low else 16#80#);
            Last  : constant Byte := (if Offset = 1 then High else 16#BF#);
         begin
            if Next not in First .. Last then
               Length := 0;
               return;
            end if;
            Code := Code * 16#40# + (Next - 16#80#);
         end;
      end loop;
   end Decode;

   function Fold (Text : String) return String is
      Result : String := Text;
      I      : Integer := Text'First;
   begin
      while I <= Text'Last loop
         if Text (I) in 'A' .. 'Z' then
            Result (I) := Character'Val (Character'Pos (Text (I)) + 32);
            I := I + 1;
         elsif At_Byte (Text, I) < 16#80# then
            I := I + 1;
         else
            declare
               Code   : Natural;
               Length : Natural;
            begin
               Decode (Text, I, Code, Length);
               if Length = 0 then
                  I := I + 1;  --  not UTF-8: the byte stays as it is
               else
                  declare
                     Lower : constant Natural :=
                       Wide_Wide_Character'Pos
                         (Ada.Wide_Wide_Characters.Handling.To_Lower (Wide_Wide_Character'Val (Code)));
                     Bytes : constant String := Encode (Lower);
                  begin
                     if Bytes'Length = Length then
                        Result (I .. I + Length - 1) := Bytes;
                     end if;
                  end;
                  I := I + Length;
               end if;
            end;
         end if;
      end loop;
      return Result;
   end Fold;

end Search.Text_Fold;

--  Case-insensitive matching, a code point at a time.
--
--  Matching used to lower-case a name, a path or a line of text a byte at a
--  time with Ada.Characters.Handling, which reads each byte as a Latin-1
--  character. On UTF-8 that is wrong twice over: "Ä" (C3 84) never matched
--  "ä" (C3 A4), because neither byte is a Latin-1 capital the other is the
--  lower case of; and the lead byte C3, read as Latin-1 'Ã', was lowered to
--  E3 -- so "Ä" became E3 84, the start of a CJK character, and matched there.
--
--  Fold decodes UTF-8 and lowers each code point with the Unicode simple
--  lowercase mapping GNAT's run-time carries (Ada.Wide_Wide_Characters.
--  Handling), so Latin, Greek, Cyrillic and the rest fold, with no data files
--  to find at run time. Bytes that are not valid UTF-8 are left as they are,
--  and so is a code point whose lower case would take a different number of
--  bytes (the Kelvin sign, capital I with dot above): a folded text keeps the
--  original's length and byte offsets, which a content match reports.
package Search.Text_Fold is

   --  Text with every code point that has a same-length lower case lowered.
   --
   --  @param Text UTF-8 text (invalid sequences pass through unchanged).
   --  @return The folded text, with Text's bounds and length.
   function Fold (Text : String) return String;

end Search.Text_Fold;

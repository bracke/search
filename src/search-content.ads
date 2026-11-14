with Regexp;

with Search.Queries;
with Search.Types;

package Search.Content is
   type Scan_Result is record
      Encoding    : Search.Types.Encoding_Kind := Search.Types.Encoding_Unknown;
      Binary      : Boolean := False;
      Match_Count : Natural := 0;
      Matches     : Search.Types.Match_Vectors.Vector;
      Diagnostics : Search.Types.Diagnostic_Vectors.Vector;
   end record;

   --  How many bytes at the start of a file decide whether it is binary: a
   --  NUL among them, as grep has it, unless the file opens with a UTF-16
   --  byte order mark.
   Binary_Sniff_Size : constant := 8 * 1024;

   --  How many bytes of a line a match's preview shows on either side of
   --  the match, and of the match itself.
   Preview_Context : constant := 200;

   --  Find Query's pattern in the file at Path, line by line.
   --
   --  The pattern comes prepared, once per query, by the caller: Needle is the
   --  literal pattern as it is compared (case-folded with Search.Text_Fold
   --  when the query ignores case), and Regex the compiled expression for a
   --  regular-expression query. A match's column and byte offsets count from
   --  1 at the start of its line.
   --
   --  The file is read in blocks onto the heap, so a long line costs no stack.
   --  A file larger than the query's maximum file size is not read: it is
   --  reported with the diagnostic content.file.too_large. One that cannot be
   --  read is reported with content.file.unreadable, and one that is gone
   --  with content.file.missing. A UTF-16 file (one with a byte order mark)
   --  is searched as the UTF-8 it decodes to.
   --
   --  @param Path The file.
   --  @param Query The query.
   --  @param Needle The literal pattern as matched.
   --  @param Regex The compiled pattern, for a regular-expression query.
   --  @return The matches, the file's encoding, and any diagnostics.
   function Scan_File
     (Path   : String;
      Query  : Search.Queries.Query;
      Needle : String;
      Regex  : Regexp.Compile_Result) return Scan_Result;

   --  The part of Line a match's preview shows: up to Preview_Context bytes
   --  before the match, the match's first Preview_Context bytes, and up to
   --  Preview_Context bytes after those. A cut never splits a UTF-8 sequence,
   --  and a side that was cut is marked with an ellipsis (U+2026). A line
   --  that fits is its own preview.
   --
   --  @param Line The matched line.
   --  @param First The match's first byte, counted from 1 at Line'First.
   --  @param Last The match's last byte, likewise (First - 1 when it is empty).
   --  @return The preview, at most 3 * Preview_Context bytes and two ellipses.
   function Preview_Of (Line : String; First : Positive; Last : Natural) return String;

   --  How many bytes of UTF-8 Decode_UTF_16 may write for Byte_Count bytes
   --  of UTF-16.
   --
   --  @param Byte_Count The length of the UTF-16 text.
   --  @return An upper bound on the length of its UTF-8.
   function UTF_8_Capacity (Byte_Count : Natural) return Natural is ((Byte_Count / 2) * 3 + 3);

   --  Decode UTF-16 to UTF-8. A leading byte order mark (U+FEFF) is dropped;
   --  a surrogate pair decodes to its supplementary code point; a lone
   --  surrogate, or an odd byte left at the end, becomes U+FFFD.
   --
   --  @param Text The UTF-16 bytes.
   --  @param Big_Endian Whether Text is UTF-16BE (else UTF-16LE).
   --  @param Into Receives the UTF-8, from Into'First.
   --  @param Last The index in Into of the last byte written.
   procedure Decode_UTF_16
     (Text       : String;
      Big_Endian : Boolean;
      Into       : out String;
      Last       : out Natural)
     with Pre => Into'Length >= UTF_8_Capacity (Text'Length) and then Into'First > 0;
end Search.Content;

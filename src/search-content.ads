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

   --  Find Query's pattern in the file at Path, line by line.
   --
   --  The pattern comes prepared, once per query, by the caller: Needle is the
   --  literal pattern as it is compared (case-folded with Search.Text_Fold
   --  when the query ignores case), and Regex the compiled expression for a
   --  regular-expression query. A match's column and byte offsets count from
   --  1 at the start of its line.
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
end Search.Content;

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

   function Scan_File
     (Path  : String;
      Query : Search.Queries.Query) return Scan_Result;
end Search.Content;

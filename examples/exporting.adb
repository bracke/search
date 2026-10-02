with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Search.Exports;
with Search.Types;

procedure Exporting is
   Results : Search.Types.Result_Vectors.Vector;
begin
   Results.Append
     (Search.Types.Search_Result'
        (Id           => 1,
         Root         => To_Unbounded_String ("."),
         Path         => To_Unbounded_String ("./README.md"),
         Name         => To_Unbounded_String ("README.md"),
         Size         => 0,
         Is_Directory => False,
         Match_Count  => 1,
         Matches      => <>,
         Freshness    => Search.Types.Fresh,
         Revision     => 1,
         Diagnostics  => <>));

   declare
      Text : constant String :=
        Search.Exports.Render (Results, Search.Types.Export_JSON);
   begin
      pragma Assert (Text'Length > 0);
   end;
end Exporting;

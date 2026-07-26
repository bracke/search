with Search.Queries;
with Search.Types;

procedure Filename_Search is
   Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
   Query   : Search.Queries.Query;
begin
   Search.Queries.Add_Root (Builder, ".");
   Search.Queries.Set_Pattern (Builder, ".adb");
   Search.Queries.Set_Mode (Builder, Search.Types.Filename_Mode);
   Query := Search.Queries.Build (Builder);
   pragma Assert (Search.Queries.Mode (Query) = Search.Types.Filename_Mode);
end Filename_Search;

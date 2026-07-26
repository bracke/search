with Search.Queries;
with Search.Types;

procedure Path_Search is
   Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
begin
   Search.Queries.Add_Root (Builder, ".");
   Search.Queries.Set_Pattern (Builder, "src");
   Search.Queries.Set_Mode (Builder, Search.Types.Path_Mode);
end Path_Search;

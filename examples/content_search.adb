with Search.Queries;
with Search.Types;

procedure Content_Search is
   Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
begin
   Search.Queries.Add_Root (Builder, ".");
   Search.Queries.Set_Pattern (Builder, "Search.Engine");
   Search.Queries.Set_Mode (Builder, Search.Types.Content_Mode);
end Content_Search;

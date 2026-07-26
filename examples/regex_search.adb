with Search.Queries;
with Search.Types;

procedure Regex_Search is
   Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
begin
   Search.Queries.Add_Root (Builder, ".");
   Search.Queries.Set_Pattern (Builder, "search[_-]?[a-z]+");
   Search.Queries.Set_Text_Mode (Builder, Search.Types.Regular_Expression);
   Search.Queries.Set_Mode (Builder, Search.Types.Combined_Mode);
end Regex_Search;

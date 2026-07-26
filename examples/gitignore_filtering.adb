with Search.Queries;

procedure Gitignore_Filtering is
   Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
begin
   Search.Queries.Add_Root (Builder, ".");
   Search.Queries.Set_Pattern (Builder, "obj");
   Search.Queries.Set_Gitignore_Aware (Builder, True);
end Gitignore_Filtering;

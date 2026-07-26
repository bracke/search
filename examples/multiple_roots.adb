with Search.Queries;

procedure Multiple_Roots is
   Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
begin
   Search.Queries.Add_Root (Builder, ".");
   Search.Queries.Add_Root (Builder, "../regexp");
   Search.Queries.Set_Pattern (Builder, "Compile");
end Multiple_Roots;

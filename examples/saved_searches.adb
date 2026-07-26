with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Search.Queries;
with Search.Settings;

procedure Saved_Searches is
   Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
   Items   : Search.Settings.Saved_Search_Vectors.Vector;
begin
   Search.Queries.Add_Root (Builder, ".");
   Search.Queries.Set_Pattern (Builder, "Search");
   Search.Settings.Add_Saved_Search
     (Items,
      (Name => To_Unbounded_String ("source references"),
       Query => Search.Queries.Build (Builder),
       View_Mode => To_Unbounded_String ("details")));
end Saved_Searches;

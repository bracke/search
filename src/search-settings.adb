with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Search.Settings is
   procedure Add_History
     (History  : in out History_Vectors.Vector;
      An_Entry : Search.Types.History_Entry;
      Limit    : Positive)
   is
   begin
      History.Prepend (An_Entry);
      while Natural (History.Length) > Limit loop
         History.Delete_Last;
      end loop;
   end Add_History;

   procedure Add_Saved_Search
     (Items : in out Saved_Search_Vectors.Vector;
      Item  : Saved_Search)
   is
   begin
      Items.Append (Item);
   end Add_Saved_Search;

   procedure Delete_Saved_Search
     (Items : in out Saved_Search_Vectors.Vector;
      Name  : String)
   is
      Index : Positive := Items.First_Index;
   begin
      while Index <= Items.Last_Index loop
         if To_String (Items.Element (Index).Name) = Name then
            Items.Delete (Index);
            return;
         end if;
         Index := Index + 1;
      end loop;
   end Delete_Saved_Search;
end Search.Settings;

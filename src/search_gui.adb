with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Search.Messages;

package body Search_GUI is
   function Command_Key (Id : Command_Id) return String is
   begin
      case Id is
         when Search_Command =>
            return "command.search";
         when Cancel_Command =>
            return "command.cancel";
         when Save_Search_Command =>
            return "command.save_search";
         when Export_Command =>
            return "command.export";
         when Open_Command =>
            return "command.open";
         when Reveal_Command =>
            return "command.reveal";
         when Toggle_Filters_Command =>
            return "command.toggle_filters";
         when Toggle_Info_Panel_Command =>
            return "command.toggle_info_panel";
         when Small_Icons_Command =>
            return "view.small_icons";
         when Large_Icons_Command =>
            return "view.large_icons";
         when Details_Command =>
            return "view.details";
      end case;
   end Command_Key;

   function Command_Label (Id : Command_Id) return String is
   begin
      return Search.Messages.Text (Command_Key (Id));
   end Command_Label;

   function To_Rows (Results : Search.Types.Result_Vectors.Vector) return Row_Vectors.Vector is
      Rows : Row_Vectors.Vector;
   begin
      for Result of Results loop
         Rows.Append
           (Result_Row'
              (Result_Id    => Result.Id,
               Display_Name => Result.Name,
               Path         => Result.Path,
               Match_Count  => Result.Match_Count,
               Freshness    => Result.Freshness));
      end loop;
      return Rows;
   end To_Rows;

   function To_Grid_Items (Rows : Row_Vectors.Vector) return Guikit.Item_Grid.Layout_Item_Vectors.Vector is
      Items : Guikit.Item_Grid.Layout_Item_Vectors.Vector;
      Index : Natural := 0;
   begin
      for Row of Rows loop
         Index := Index + 1;
         Items.Append
           (Guikit.Item_Grid.Layout_Item'
              (Visible_Index => Index,
               Group_Header  => False,
               Label         => Row.Display_Name));
      end loop;
      return Items;
   end To_Grid_Items;

   function Build_Info_Panel (Result : Search.Types.Search_Result) return Info_Panel_Model is
      Preview : UString;
   begin
      if not Result.Matches.Is_Empty then
         Preview := Result.Matches.First_Element.Preview;
      end if;

      return
        (Metadata_Key      => To_Unbounded_String ("panel.metadata"),
         Summary_Key       => To_Unbounded_String ("panel.summary"),
         Match_Count       => Result.Match_Count,
         Diagnostics_Count => Natural (Result.Diagnostics.Length),
         Preview           => Preview,
         Freshness         => Result.Freshness);
   end Build_Info_Panel;
end Search_GUI;

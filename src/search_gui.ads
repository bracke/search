with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Guikit.Item_Grid;

with Search.Types;

package Search_GUI is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   type Command_Id is
     (Search_Command,
      Cancel_Command,
      Save_Search_Command,
      Export_Command,
      Open_Command,
      Reveal_Command,
      Toggle_Filters_Command,
      Toggle_Info_Panel_Command,
      Small_Icons_Command,
      Large_Icons_Command,
      Details_Command);

   function Command_Key (Id : Command_Id) return String;

   --  The localized label for a command, resolved from Command_Key through the
   --  message catalog.
   function Command_Label (Id : Command_Id) return String;

   type View_Mode is (Small_Icons, Large_Icons, Details);

   type Result_Row is record
      Result_Id   : Natural := 0;
      Display_Name : UString;
      Path         : UString;
      Match_Count  : Natural := 0;
      Freshness    : Search.Types.Freshness_State := Search.Types.Fresh;
   end record;

   package Row_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Result_Row);

   type Info_Panel_Model is record
      Metadata_Key      : UString;
      Summary_Key       : UString;
      Match_Count       : Natural := 0;
      Diagnostics_Count : Natural := 0;
      Preview           : UString;
      Freshness         : Search.Types.Freshness_State := Search.Types.Fresh;
   end record;

   function To_Rows (Results : Search.Types.Result_Vectors.Vector) return Row_Vectors.Vector;
   function To_Grid_Items (Rows : Row_Vectors.Vector) return Guikit.Item_Grid.Layout_Item_Vectors.Vector;
   function Build_Info_Panel (Result : Search.Types.Search_Result) return Info_Panel_Model;
end Search_GUI;

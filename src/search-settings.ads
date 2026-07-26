with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Search.Queries;
with Search.Types;
use type Search.Types.History_Entry;

package Search.Settings is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   type Settings_Model is record
      Window_Width       : Natural := 0;
      Window_Height      : Natural := 0;
      Info_Panel_Open    : Boolean := True;
      Default_Query      : Search.Queries.Query;
      History_Limit      : Positive := 50;
      Batch_Size         : Positive := 64;
      Worker_Count       : Positive := 2;
      View_Mode          : UString;
   end record;

   type Saved_Search is record
      Name  : UString;
      Query : Search.Queries.Query;
      View_Mode : UString;
   end record;

   package Saved_Search_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Saved_Search);

   package History_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Search.Types.History_Entry);

   procedure Add_History
     (History  : in out History_Vectors.Vector;
      An_Entry : Search.Types.History_Entry;
      Limit    : Positive);

   procedure Add_Saved_Search
     (Items : in out Saved_Search_Vectors.Vector;
      Item  : Saved_Search);

   procedure Delete_Saved_Search
     (Items : in out Saved_Search_Vectors.Vector;
      Name  : String);
end Search.Settings;

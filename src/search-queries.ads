with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Search.Types;

package Search.Queries is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   use type Ada.Strings.Unbounded.Unbounded_String;

   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => UString);

   type Query is private;
   type Query_Builder is private;

   function New_Builder return Query_Builder;
   procedure Add_Root (Builder : in out Query_Builder; Root : String);
   procedure Set_Pattern (Builder : in out Query_Builder; Pattern : String);
   procedure Set_Mode (Builder : in out Query_Builder; Mode : Search.Types.Search_Mode);
   procedure Set_Text_Mode (Builder : in out Query_Builder; Mode : Search.Types.Text_Mode);
   procedure Set_Recursive (Builder : in out Query_Builder; Enabled : Boolean);
   procedure Set_Max_Depth (Builder : in out Query_Builder; Depth : Natural);
   procedure Set_Hidden_Policy (Builder : in out Query_Builder; Policy : Search.Types.Hidden_Policy);
   procedure Set_Symlink_Policy (Builder : in out Query_Builder; Policy : Search.Types.Symlink_Policy);
   procedure Set_Gitignore_Aware (Builder : in out Query_Builder; Enabled : Boolean);
   procedure Set_Case_Sensitive (Builder : in out Query_Builder; Enabled : Boolean);
   procedure Set_Content_Context_Lines (Builder : in out Query_Builder; Lines : Natural);
   procedure Set_Max_File_Size (Builder : in out Query_Builder; Bytes : Long_Long_Integer);
   function Build (Builder : Query_Builder) return Query;

   function Roots (Value : Query) return String_Vectors.Vector;
   function Pattern (Value : Query) return String;
   function Mode (Value : Query) return Search.Types.Search_Mode;
   function Text_Mode (Value : Query) return Search.Types.Text_Mode;
   function Recursive (Value : Query) return Boolean;
   function Max_Depth (Value : Query) return Natural;
   function Hidden_Policy (Value : Query) return Search.Types.Hidden_Policy;
   function Symlink_Policy (Value : Query) return Search.Types.Symlink_Policy;
   function Gitignore_Aware (Value : Query) return Boolean;
   function Case_Sensitive (Value : Query) return Boolean;
   function Content_Context_Lines (Value : Query) return Natural;
   function Max_File_Size (Value : Query) return Long_Long_Integer;

   function Validate (Value : Query) return Search.Types.Diagnostic_Vectors.Vector;

private
   type Query_Data is record
      Roots                 : String_Vectors.Vector;
      Pattern               : UString;
      Mode                  : Search.Types.Search_Mode := Search.Types.Filename_Mode;
      Text_Mode             : Search.Types.Text_Mode := Search.Types.Literal_Text;
      Recursive             : Boolean := True;
      Max_Depth             : Natural := 0;
      Hidden_Policy         : Search.Types.Hidden_Policy := Search.Types.Exclude_Hidden;
      Symlink_Policy        : Search.Types.Symlink_Policy := Search.Types.Do_Not_Follow_Symlinks;
      Gitignore_Aware       : Boolean := True;
      Case_Sensitive        : Boolean := False;
      Content_Context_Lines : Natural := 2;
      Max_File_Size         : Long_Long_Integer := 64 * 1024 * 1024;
   end record;

   type Query is record
      Data : Query_Data;
   end record;

   type Query_Builder is record
      Data : Query_Data;
   end record;
end Search.Queries;

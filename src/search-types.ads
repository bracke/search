with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada.Calendar;

package Search.Types is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   type Search_Mode is (Filename_Mode, Path_Mode, Content_Mode, Combined_Mode);
   type Text_Mode is (Literal_Text, Regular_Expression);
   type Symlink_Policy is (Do_Not_Follow_Symlinks, Follow_File_Symlinks, Follow_All_Symlinks);
   type Hidden_Policy is (Exclude_Hidden, Include_Hidden);
   type Completion_State is (Not_Started, Completed, Cancelled, Failed);
   type Diagnostic_Severity is (Info, Warning, Error);
   type Encoding_Kind is (Encoding_UTF_8, Encoding_UTF_16_LE, Encoding_UTF_16_BE, Encoding_Binary, Encoding_Unknown);
   type Freshness_State is (Fresh, Changed, Missing);
   type Export_Format is (Export_JSON, Export_CSV, Export_Text);

   type Diagnostic is record
      Severity : Diagnostic_Severity := Info;
      Code     : UString;
      Path     : UString;
      Message  : UString;
   end record;

   package Diagnostic_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Diagnostic);

   type Content_Match is record
      Line       : Positive := 1;
      Column     : Positive := 1;
      First_Byte : Natural := 0;
      Last_Byte  : Natural := 0;
      Preview    : UString;
   end record;

   package Match_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Content_Match);

   type Search_Result is record
      Id          : Natural := 0;
      Root        : UString;
      Path        : UString;
      Name        : UString;
      Size        : Long_Long_Integer := 0;
      Is_Directory : Boolean := False;
      Match_Count : Natural := 0;
      Matches     : Match_Vectors.Vector;
      Freshness   : Freshness_State := Fresh;
      Revision    : Natural := 0;
      Diagnostics : Diagnostic_Vectors.Vector;
   end record;

   package Result_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Search_Result);

   type Result_Batch is record
      Sequence    : Natural := 0;
      Results     : Result_Vectors.Vector;
      Diagnostics : Diagnostic_Vectors.Vector;
      Final       : Boolean := False;
   end record;

   type History_Entry is record
      Timestamp  : Ada.Calendar.Time := Ada.Calendar.Clock;
      State      : Completion_State := Not_Started;
      Duration_Ms : Natural := 0;
   end record;
end Search.Types;

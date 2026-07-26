with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Regexp;

package body Search.Queries is
   use type Search.Types.Text_Mode;
   use type Regexp.Compile_Status;

   function New_Builder return Query_Builder is
   begin
      return (Data => <>);
   end New_Builder;

   procedure Add_Root (Builder : in out Query_Builder; Root : String) is
   begin
      if Root'Length > 0 then
         Builder.Data.Roots.Append (To_Unbounded_String (Root));
      end if;
   end Add_Root;

   procedure Set_Pattern (Builder : in out Query_Builder; Pattern : String) is
   begin
      Builder.Data.Pattern := To_Unbounded_String (Pattern);
   end Set_Pattern;

   procedure Set_Mode (Builder : in out Query_Builder; Mode : Search.Types.Search_Mode) is
   begin
      Builder.Data.Mode := Mode;
   end Set_Mode;

   procedure Set_Text_Mode (Builder : in out Query_Builder; Mode : Search.Types.Text_Mode) is
   begin
      Builder.Data.Text_Mode := Mode;
   end Set_Text_Mode;

   procedure Set_Recursive (Builder : in out Query_Builder; Enabled : Boolean) is
   begin
      Builder.Data.Recursive := Enabled;
   end Set_Recursive;

   procedure Set_Max_Depth (Builder : in out Query_Builder; Depth : Natural) is
   begin
      Builder.Data.Max_Depth := Depth;
   end Set_Max_Depth;

   procedure Set_Hidden_Policy (Builder : in out Query_Builder; Policy : Search.Types.Hidden_Policy) is
   begin
      Builder.Data.Hidden_Policy := Policy;
   end Set_Hidden_Policy;

   procedure Set_Symlink_Policy (Builder : in out Query_Builder; Policy : Search.Types.Symlink_Policy) is
   begin
      Builder.Data.Symlink_Policy := Policy;
   end Set_Symlink_Policy;

   procedure Set_Gitignore_Aware (Builder : in out Query_Builder; Enabled : Boolean) is
   begin
      Builder.Data.Gitignore_Aware := Enabled;
   end Set_Gitignore_Aware;

   procedure Set_Case_Sensitive (Builder : in out Query_Builder; Enabled : Boolean) is
   begin
      Builder.Data.Case_Sensitive := Enabled;
   end Set_Case_Sensitive;

   procedure Set_Content_Context_Lines (Builder : in out Query_Builder; Lines : Natural) is
   begin
      Builder.Data.Content_Context_Lines := Lines;
   end Set_Content_Context_Lines;

   procedure Set_Max_File_Size (Builder : in out Query_Builder; Bytes : Long_Long_Integer) is
   begin
      Builder.Data.Max_File_Size := Bytes;
   end Set_Max_File_Size;

   function Build (Builder : Query_Builder) return Query is
   begin
      return (Data => Builder.Data);
   end Build;

   function Roots (Value : Query) return String_Vectors.Vector is (Value.Data.Roots);
   function Pattern (Value : Query) return String is (To_String (Value.Data.Pattern));
   function Mode (Value : Query) return Search.Types.Search_Mode is (Value.Data.Mode);
   function Text_Mode (Value : Query) return Search.Types.Text_Mode is (Value.Data.Text_Mode);
   function Recursive (Value : Query) return Boolean is (Value.Data.Recursive);
   function Max_Depth (Value : Query) return Natural is (Value.Data.Max_Depth);
   function Hidden_Policy (Value : Query) return Search.Types.Hidden_Policy is (Value.Data.Hidden_Policy);
   function Symlink_Policy (Value : Query) return Search.Types.Symlink_Policy is (Value.Data.Symlink_Policy);
   function Gitignore_Aware (Value : Query) return Boolean is (Value.Data.Gitignore_Aware);
   function Case_Sensitive (Value : Query) return Boolean is (Value.Data.Case_Sensitive);
   function Content_Context_Lines (Value : Query) return Natural is (Value.Data.Content_Context_Lines);
   function Max_File_Size (Value : Query) return Long_Long_Integer is (Value.Data.Max_File_Size);

   function Make_Diagnostic
     (Code : String;
      Text : String) return Search.Types.Diagnostic
   is
   begin
      return
        (Severity => Search.Types.Error,
         Code     => To_Unbounded_String (Code),
         Path     => Null_Unbounded_String,
         Message  => To_Unbounded_String (Text));
   end Make_Diagnostic;

   function Validate (Value : Query) return Search.Types.Diagnostic_Vectors.Vector is
      Diagnostics : Search.Types.Diagnostic_Vectors.Vector;
   begin
      if Value.Data.Roots.Is_Empty then
         Diagnostics.Append (Make_Diagnostic ("query.roots.missing", "query.roots.missing"));
      end if;

      if Length (Value.Data.Pattern) = 0 then
         Diagnostics.Append (Make_Diagnostic ("query.pattern.empty", "query.pattern.empty"));
      end if;

      for Root of Value.Data.Roots loop
         if To_String (Root)'Length = 0 or else not Ada.Directories.Exists (To_String (Root)) then
            Diagnostics.Append
              (Search.Types.Diagnostic'
                 (Severity => Search.Types.Error,
                  Code     => To_Unbounded_String ("query.root.not_found"),
                  Path     => Root,
                  Message  => To_Unbounded_String ("query.root.not_found")));
         end if;
      end loop;

      if Value.Data.Text_Mode = Search.Types.Regular_Expression and then Length (Value.Data.Pattern) > 0 then
         declare
            Compiled : constant Regexp.Compile_Result := Regexp.Compile (To_String (Value.Data.Pattern));
         begin
            if Compiled.Status /= Regexp.Compile_Ok then
               Diagnostics.Append
                 (Search.Types.Diagnostic'
                    (Severity => Search.Types.Error,
                     Code     => To_Unbounded_String ("query.regex.invalid"),
                     Path     => Null_Unbounded_String,
                     Message  => To_Unbounded_String ("query.regex.invalid")));
            end if;
         end;
      end if;

      if Value.Data.Max_File_Size < 0 then
         Diagnostics.Append (Make_Diagnostic ("query.max_file_size.invalid", "query.max_file_size.invalid"));
      end if;

      return Diagnostics;
   end Validate;
end Search.Queries;

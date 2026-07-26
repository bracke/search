with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;

with Messages.Arguments;
with Messages.Result;
with Messages.Runtime;

package body Search.Messages is

   --  Catalog text is rendered through the messages crate, so it can be
   --  localized. Standard.Messages disambiguates the top-level crate from this
   --  Search.Messages package.
   Runtime     : Standard.Messages.Runtime.Instance;
   Locale      : Unbounded_String := To_Unbounded_String ("en");
   Initialized : Boolean := False;

   --  share/search.catalog resolved relative to the working directory, with
   --  build-tree fallbacks (the app runs from its install prefix, the tests
   --  from the tests crate).
   function Catalog_Path return String is
   begin
      if Ada.Directories.Exists ("share/search.catalog") then
         return "share/search.catalog";
      elsif Ada.Directories.Exists ("../share/search.catalog") then
         return "../share/search.catalog";
      elsif Ada.Directories.Exists ("../../share/search.catalog") then
         return "../../share/search.catalog";
      else
         return "share/search.catalog";
      end if;
   end Catalog_Path;

   --  The system locale's language part (LC_ALL, then LC_MESSAGES, then LANG),
   --  or "en" for an empty, C, or POSIX value.
   function Detected_Locale return String is
      function Env (Name : String) return String is
        (if Ada.Environment_Variables.Exists (Name)
         then Ada.Environment_Variables.Value (Name)
         else "");

      Raw  : constant String :=
        (if Env ("LC_ALL") /= "" then Env ("LC_ALL")
         elsif Env ("LC_MESSAGES") /= "" then Env ("LC_MESSAGES")
         else Env ("LANG"));
      Last : Natural := Raw'First - 1;
   begin
      for Index in Raw'Range loop
         exit when Raw (Index) in '.' | '@' | '_';
         Last := Index;
      end loop;

      if Last < Raw'First then
         return "en";
      end if;

      declare
         Language : constant String := Raw (Raw'First .. Last);
      begin
         if Language = "C" or else Language = "POSIX" then
            return "en";
         end if;
         return Language;
      end;
   end Detected_Locale;

   procedure Ensure_Initialized is
   begin
      if not Initialized then
         Standard.Messages.Runtime.Initialize (Runtime, Catalog_Path);
         Locale := To_Unbounded_String (Detected_Locale);
         Initialized := True;
      end if;
   end Ensure_Initialized;

   function Text (Key : String) return String is
      use type Standard.Messages.Result.Render_Status;
      Args : Standard.Messages.Arguments.Arguments;
   begin
      Ensure_Initialized;

      declare
         Result : constant Standard.Messages.Result.Render_Result :=
           Standard.Messages.Runtime.Render
             (Item      => Runtime,
              Locale    => To_String (Locale),
              Key       => Key,
              Arguments => Args);
      begin
         if Result.Status = Standard.Messages.Result.Success then
            return Standard.Messages.Result.Output_Text (Result.Text);
         end if;
      end;

      --  Key absent from the catalog: return it unchanged.
      return Key;
   end Text;

end Search.Messages;

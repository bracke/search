with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Hostkit.Fs;

with Guikit.Fonts;

--  The chain is guikit's (Guikit.Fonts), the one every guikit application
--  draws with; search contributes only where its host keeps fonts. It used to
--  take files' font set-up (Files.Fonts), which pulled the whole file manager
--  into search for this one package.
package body Search.Fonts is

   --  The host's font folders, the system's first.
   function Font_Directories return Guikit.Text.Font_Path_Vectors.Vector is
      Result : Guikit.Text.Font_Path_Vectors.Vector;
   begin
      for Folder of Hostkit.Fs.Font_Directories loop
         Result.Append (Ada.Strings.Unbounded.To_String (Folder));
      end loop;
      return Result;
   exception
      --  No host folders: the known whole paths are still looked for, so the
      --  window still opens -- but says why its fonts may be poor.
      when Error : others =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "search-desktop: the host's font folders could not be read ("
            & Ada.Exceptions.Exception_Name (Error) & ": "
            & Ada.Exceptions.Exception_Message (Error)
            & "); looking only in the known font locations");
         return Result;
   end Font_Directories;

   function Primary return String is
     (Guikit.Fonts.Default_Font_Path (Font_Directories => Font_Directories));

   --  No image decoder is linked -- neither guikit nor textrender carries a PNG
   --  decoder, and files' was the only one -- so the bitmap emoji fonts are left
   --  out and only the layered (COLR) kind, which textrender draws unaided, is
   --  listed. An emoji with no COLR font installed draws monochrome.
   function Fallbacks return Guikit.Text.Font_Path_Vectors.Vector is
     (Guikit.Fonts.Fallback_Font_Paths
        (Primary          => Primary,
         Font_Directories => Font_Directories,
         Colour_Bitmaps   => False));

end Search.Fonts;

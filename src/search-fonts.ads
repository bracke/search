with Guikit.Text;

--  Font discovery for search-desktop: guikit's monospace primary face and
--  fallback chain (Guikit.Fonts), looked for in the host's font folders, so
--  names with the odd non-Latin glyph or emoji still render. Only fonts that
--  load are returned.
package Search.Fonts is

   --  Path to the monospace primary font, or "" if no usable font is
   --  present on this system.
   --
   --  @return A loadable font path, or the empty string.
   function Primary return String;

   --  Loadable fallback font paths (broad Unicode / symbol faces, then the
   --  layered colour emoji fonts), in order.
   --
   --  @return The fallback font paths.
   function Fallbacks return Guikit.Text.Font_Path_Vectors.Vector;

end Search.Fonts;

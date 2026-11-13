with Hostkit.Host;
with Hostkit.Resources;

with Messages.Program_Catalog;

--  The catalogue wrapper is the messages crate's (Messages.Program_Catalog),
--  shared with launcher; search says only where its catalogue is and asks
--  the host for its locale, so Windows and macOS render in the user's
--  language when no LANG is set rather than always in English.
package body Search.Messages is

   --  share/search.catalog found from the program's own executable (beside it,
   --  or above an installed bin/ or a tests/bin/), never from the directory it
   --  was started in.
   function Catalog_Path return String is
     (Hostkit.Resources.Beside_Executable ("share/search.catalog"));

   --  Standard.Messages disambiguates the top-level crate from this
   --  Search.Messages package.
   package Catalog is new Standard.Messages.Program_Catalog
     (Catalog_Path  => Catalog_Path,
      Native_Locale => Hostkit.Host.Native_Locale);

   function Text (Key : String) return String renames Catalog.Text;

end Search.Messages;

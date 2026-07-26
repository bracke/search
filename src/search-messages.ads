package Search.Messages is
   --  Return the localized text for a catalog Key (for example "command.search"
   --  or "app.name"), rendered through the messages crate against
   --  share/search.catalog. Falls back to Key when it is absent from the
   --  catalog.
   function Text (Key : String) return String;
end Search.Messages;

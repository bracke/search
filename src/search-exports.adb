with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Search.Exports is
   function Escape_JSON (Text : String) return String is
      Result : Unbounded_String;
   begin
      for Ch of Text loop
         case Ch is
            when '"' =>
               Append (Result, "\""");
            when '\' =>
               Append (Result, "\\");
            when ASCII.LF =>
               Append (Result, "\n");
            when others =>
               Append (Result, Ch);
         end case;
      end loop;
      return To_String (Result);
   end Escape_JSON;

   function Escape_CSV (Text : String) return String is
      Result : Unbounded_String := To_Unbounded_String ("""");
   begin
      for Ch of Text loop
         if Ch = '"' then
            Append (Result, """""");
         else
            Append (Result, Ch);
         end if;
      end loop;
      Append (Result, """");
      return To_String (Result);
   end Escape_CSV;

   function Render_JSON (Results : Search.Types.Result_Vectors.Vector) return String is
      Output : Unbounded_String := To_Unbounded_String ("[");
      First  : Boolean := True;
   begin
      for Result of Results loop
         if not First then
            Append (Output, ",");
         end if;
         First := False;
         Append
           (Output,
            "{""id"":" & Natural'Image (Result.Id) &
            ",""path"":""" & Escape_JSON (To_String (Result.Path)) &
            """,""name"":""" & Escape_JSON (To_String (Result.Name)) &
            """,""matches"":" & Natural'Image (Result.Match_Count) & "}");
      end loop;
      Append (Output, "]");
      return To_String (Output);
   end Render_JSON;

   function Render_CSV (Results : Search.Types.Result_Vectors.Vector) return String is
      Output : Unbounded_String := To_Unbounded_String ("id,path,name,matches" & ASCII.LF);
   begin
      for Result of Results loop
         Append
           (Output,
            Natural'Image (Result.Id) & "," &
            Escape_CSV (To_String (Result.Path)) & "," &
            Escape_CSV (To_String (Result.Name)) & "," &
            Natural'Image (Result.Match_Count) & ASCII.LF);
      end loop;
      return To_String (Output);
   end Render_CSV;

   function Render_Text (Results : Search.Types.Result_Vectors.Vector) return String is
      Output : Unbounded_String;
   begin
      for Result of Results loop
         Append
           (Output,
            To_String (Result.Path) & " [" & Natural'Image (Result.Match_Count) & "]" & ASCII.LF);
      end loop;
      return To_String (Output);
   end Render_Text;

   function Render
     (Results : Search.Types.Result_Vectors.Vector;
      Format  : Search.Types.Export_Format) return String is
   begin
      case Format is
         when Search.Types.Export_JSON =>
            return Render_JSON (Results);
         when Search.Types.Export_CSV =>
            return Render_CSV (Results);
         when Search.Types.Export_Text =>
            return Render_Text (Results);
      end case;
   end Render;
end Search.Exports;

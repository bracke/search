with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Glfw;
with Glfw.Input.Keys;
with Glfw.Windows;

with Guikit.Draw;
with Guikit.Text;
with Guikit.Utf8;
with Guikit.Vulkan;
with Guikit.Widgets;

with Files.Fonts;

--  Windowed front end for the search tool. Increment 1: a window with an
--  efficient (event-driven, present-skipping) render loop that draws the query
--  input field and the text typed into it. Running the search and rendering the
--  result grid come in later increments.
procedure Search.Desktop is

   Line_Height : constant Positive := 26;

   --  GLFW window subclass: the input callbacks stash events into these pending
   --  fields, which the main loop drains once per frame. Dirty starts True so
   --  the first frame draws; the loop redraws only when it is set, so an idle
   --  window stops re-presenting the same frame.
   type Search_Window is new Glfw.Windows.Window with record
      Pending_Text      : Unbounded_String := Null_Unbounded_String;
      Pending_Escape    : Boolean := False;
      Pending_Backspace : Natural := 0;
      Dirty             : Boolean := True;
   end record;

   type Window_Access is access all Search_Window;

   function As_Window (Handle : Window_Access) return Glfw.Windows.Window_Reference is
     (Glfw.Windows.Window_Reference (Handle));

   overriding procedure Character_Entered
     (Object : not null access Search_Window;
      Char   : Wide_Wide_Character);
   overriding procedure Key_Changed
     (Object   : not null access Search_Window;
      Key      : Glfw.Input.Keys.Key;
      Scancode : Glfw.Input.Keys.Scancode;
      Action   : Glfw.Input.Keys.Action;
      Mods     : Glfw.Input.Keys.Modifiers);

   overriding procedure Character_Entered
     (Object : not null access Search_Window;
      Char   : Wide_Wide_Character)
   is
      Code : constant Natural := Wide_Wide_Character'Pos (Char);
   begin
      if Code >= Character'Pos (' ') then
         Append (Object.Pending_Text, Guikit.Utf8.Encode (Code));
         Object.Dirty := True;
      end if;
   end Character_Entered;

   overriding procedure Key_Changed
     (Object   : not null access Search_Window;
      Key      : Glfw.Input.Keys.Key;
      Scancode : Glfw.Input.Keys.Scancode;
      Action   : Glfw.Input.Keys.Action;
      Mods     : Glfw.Input.Keys.Modifiers)
   is
      use type Glfw.Input.Keys.Action;
      use type Glfw.Input.Keys.Key;
      pragma Unreferenced (Scancode, Mods);
   begin
      if Action = Glfw.Input.Keys.Release then
         return;
      end if;
      Object.Dirty := True;
      if Key = Glfw.Input.Keys.Escape then
         Object.Pending_Escape := True;
      elsif Key = Glfw.Input.Keys.Backspace then
         Object.Pending_Backspace := Object.Pending_Backspace + 1;
      end if;
   end Key_Changed;

   --  Drop the last UTF-8 codepoint from Text (a byte-at-a-time delete would
   --  corrupt a multibyte character).
   procedure Backspace_Codepoint (Text : in out Unbounded_String) is
      Raw : constant String := To_String (Text);
      Last : Natural := Raw'Last;
   begin
      if Raw'Length = 0 then
         return;
      end if;
      while Last > Raw'First
        and then Character'Pos (Raw (Last)) in 16#80# .. 16#BF#
      loop
         Last := Last - 1;
      end loop;
      Text := To_Unbounded_String (Raw (Raw'First .. Last - 1));
   end Backspace_Codepoint;

   Handle       : constant Window_Access := new Search_Window;
   Vulkan       : Guikit.Vulkan.Vulkan_Renderer;
   Text         : Guikit.Text.Renderer;
   Ignore_St    : Guikit.Vulkan.Vulkan_Status;
   Ignore_Ts    : Guikit.Draw.Text_Render_Status;
   Query        : Unbounded_String := Null_Unbounded_String;
   Last_Frame_W : Glfw.Size := 0;
   Last_Frame_H : Glfw.Size := 0;

   --  Render one frame: bring the swapchain up, draw the query field and its
   --  text, and present.
   procedure Draw_Frame
     (Win : Window_Access;
      Vk  : in out Guikit.Vulkan.Vulkan_Renderer;
      Txt : in out Guikit.Text.Renderer)
   is
      Window_W, Window_H : Glfw.Size;
      Frame_W,  Frame_H  : Glfw.Size;
   begin
      Glfw.Windows.Get_Size (As_Window (Win), Window_W, Window_H);
      Glfw.Windows.Get_Framebuffer_Size (As_Window (Win), Frame_W, Frame_H);
      Guikit.Vulkan.Ensure_Ready (Vk, As_Window (Win), Natural (Frame_W), Natural (Frame_H));
      if not Guikit.Vulkan.Swapchain_Ready (Vk) then
         return;
      end if;

      declare
         Rects  : Guikit.Draw.Rectangle_Command_Vectors.Vector;
         Texts  : Guikit.Draw.Text_Command_Vectors.Vector;
         No_Tri        : Guikit.Draw.Triangle_Command_Vectors.Vector;
         No_Icons      : Guikit.Draw.Icon_Command_Vectors.Vector;
         No_Overlay    : Guikit.Draw.Rectangle_Command_Vectors.Vector;
         No_Overlay_Tx : Guikit.Draw.Text_Command_Vectors.Vector;
         W : constant Natural := Natural (Window_W);
         H : constant Natural := Natural (Window_H);
         Margin  : constant Natural := 16;
         Field_H : constant Natural := Line_Height + 12;
         Field_W : constant Natural := (if W > 2 * Margin then W - 2 * Margin else 0);
         Query_Str : constant String := To_String (Query);
         Shown     : constant String :=
           (if Query_Str = "" then "Search..." else Query_Str);
         Text_Col  : constant Guikit.Draw.Render_Color :=
           (if Query_Str = "" then Guikit.Draw.Muted_Text_Color
            else Guikit.Draw.Text_Color);
         Metrics : constant Guikit.Draw.Layout_Metrics :=
           (Width => W, Height => H, others => 0);
         Glyphs  : Guikit.Draw.Text_Render_Result;
         Batch   : Guikit.Vulkan.Submission_Batch;
      begin
         Guikit.Widgets.Draw_Input_Field
           (Rectangles   => Rects,
            Clip_Width   => W,
            Clip_Height  => H,
            X            => Margin,
            Y            => Margin,
            Width        => Field_W,
            Height       => Field_H,
            Fill_Color   => Guikit.Draw.Input_Color,
            Border_Color => Guikit.Draw.Border_Color);

         Texts.Append
           (Guikit.Draw.Text_Command'
              (X      => Margin + 8,
               Y      => Margin + 6,
               Width  => (if Field_W > 16 then Field_W - 16 else 0),
               Height => Line_Height,
               Text   => To_Unbounded_String (Shown),
               Color  => Text_Col,
               others => <>));

         Glyphs := Guikit.Text.Build_Glyphs (Txt, Texts, No_Overlay_Tx);
         Batch  :=
           Guikit.Vulkan.Build_Submission
             (Rects, No_Tri, No_Icons, No_Overlay, Metrics,
              Guikit.Draw.Theme_Dark, Glyphs);
         Ignore_St :=
           Guikit.Vulkan.Present_Frame (Vk, Batch, Natural (Frame_W), Natural (Frame_H));
      end;
   end Draw_Frame;

begin
   --  Load the fonts (reused from the files project, which search depends on).
   declare
      Fallbacks : Guikit.Text.Font_Path_Vectors.Vector;
   begin
      if Files.Fonts.Default_Font_Path = "" then
         return;
      end if;
      for Path of Files.Fonts.Fallback_Font_Paths loop
         Fallbacks.Append (To_String (Path));
      end loop;
      Ignore_Ts :=
        Guikit.Text.Initialize
          (Text, Files.Fonts.Default_Font_Path, Fallbacks,
           Pixel_Size   => 18,
           Cell_Width   => 14,
           Cell_Height  => Line_Height,
           Atlas_Width  => 1024,
           Atlas_Height => 1024);
   end;

   --  Create the window.
   Glfw.Init;
   Guikit.Vulkan.Configure_Window_Hints;
   Glfw.Windows.Init (As_Window (Handle), Glfw.Size (900), Glfw.Size (560), "search");
   Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Char);
   Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Key);
   Glfw.Windows.Show (As_Window (Handle));

   --  Main loop. Event-driven: block until an event (with a defensive 1s cap),
   --  then redraw only when something changed.
   while not Glfw.Windows.Should_Close (As_Window (Handle)) loop
      Guikit.Vulkan.Wait_For_Events (1.0);
      Guikit.Vulkan.Poll_Events;

      if Length (Handle.Pending_Text) > 0 then
         Append (Query, Handle.Pending_Text);
         Handle.Pending_Text := Null_Unbounded_String;
      end if;
      for I in 1 .. Handle.Pending_Backspace loop
         Backspace_Codepoint (Query);
      end loop;
      Handle.Pending_Backspace := 0;
      exit when Handle.Pending_Escape;

      declare
         Frame_W, Frame_H : Glfw.Size;
      begin
         --  A resize is not delivered through the input callbacks, so detect it
         --  here and mark dirty; otherwise the resized window would not repaint.
         Glfw.Windows.Get_Framebuffer_Size (As_Window (Handle), Frame_W, Frame_H);
         if Natural (Frame_W) /= Natural (Last_Frame_W)
           or else Natural (Frame_H) /= Natural (Last_Frame_H)
         then
            Handle.Dirty := True;
            Last_Frame_W := Frame_W;
            Last_Frame_H := Frame_H;
         end if;

         --  Redraw only when something changed; otherwise the identical frame is
         --  already on screen and the build/submit/present path is skipped.
         if Handle.Dirty or else Guikit.Vulkan.Readback_Enabled (Vulkan) then
            Draw_Frame (Handle, Vulkan, Text);
            Handle.Dirty := False;
         end if;
      end;
   end loop;
end Search.Desktop;

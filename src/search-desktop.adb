with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Glfw;
with Glfw.Input.Keys;
with Glfw.Windows;

with Guikit.Draw;
with Guikit.Input.Pending;
with Guikit.Item_Grid;
with Guikit.Layout;
with Guikit.Text;
with Guikit.Utf8;
with Guikit.Utf8.Editing;
with Guikit.Vulkan;
with Guikit.Widgets;

with Search.Engine;
with Search.Fonts;
with Search.Queries;
with Search.Types;

with Search_GUI;

--  Windowed front end for the search tool. A GLFW/Vulkan window with an
--  efficient (event-driven, present-skipping) render loop: type a pattern, press
--  Enter to run the search under the root (argv(1), or "."), and the results are
--  drawn as a selectable list via the Search_GUI -> Guikit.Item_Grid mapping.
procedure Search.Desktop is

   Line_Height : constant Positive := 26;

   --  The window keeps its input in one ordered queue (Guikit.Input.Pending),
   --  which the main loop drains once per frame; its callbacks guard against
   --  an exception unwinding into GLFW's C code. Its dirty flag starts set so
   --  the first frame draws; the loop redraws only when it is set, so an idle
   --  window stops re-presenting the same frame.
   type Search_Window is new Guikit.Input.Pending.Pending_Window with null record;

   type Window_Access is access all Search_Window;

   function As_Window (Handle : Window_Access) return Glfw.Windows.Window_Reference is
     (Glfw.Windows.Window_Reference (Handle));

   --  Delete the character before the end of Text -- a code point with the
   --  combining marks after it, as every guikit text field deletes -- not a
   --  byte, which would corrupt a multibyte character, nor a bare code point,
   --  which would leave an accent's mark behind.
   procedure Backspace (Text : in out Unbounded_String) is
      Ignored_Cursor : Natural;
      Raw            : constant String := To_String (Text);
   begin
      Guikit.Utf8.Editing.Delete_At
        (Text       => Raw,
         Cursor     => Raw'Length,
         Backward   => True,
         By_Word    => False,
         New_Text   => Text,
         New_Cursor => Ignored_Cursor);
   end Backspace;

   Handle       : constant Window_Access := new Search_Window;
   Vulkan       : Guikit.Vulkan.Vulkan_Renderer;
   Text         : Guikit.Text.Renderer;
   Ignore_St    : Guikit.Vulkan.Vulkan_Status;
   Ignore_Ts    : Guikit.Draw.Text_Render_Status;
   Query        : Unbounded_String := Null_Unbounded_String;
   --  Headless render check: "--smoke <root> <pattern>" runs a real search and
   --  confirms the query field and results region hold ink, then exits.
   Smoke        : constant Boolean :=
     Ada.Command_Line.Argument_Count >= 1
     and then Ada.Command_Line.Argument (1) = "--smoke";
   Root         : constant String :=
     (if Smoke then
        (if Ada.Command_Line.Argument_Count >= 2 then Ada.Command_Line.Argument (2) else ".")
      elsif Ada.Command_Line.Argument_Count >= 1 then Ada.Command_Line.Argument (1)
      else ".");
   Smoke_Pattern : constant String :=
     (if Smoke and then Ada.Command_Line.Argument_Count >= 3
      then Ada.Command_Line.Argument (3) else "");
   Rows         : Search_GUI.Row_Vectors.Vector;
   Grid_Items   : Guikit.Item_Grid.Layout_Item_Vectors.Vector;
   Selected     : Natural := 0;
   Last_Frame_W : Glfw.Size := 0;
   Last_Frame_H : Glfw.Size := 0;
   --  Escape was pressed: the loop ends.
   Quit         : Boolean := False;

   --  Run the search for the current query under Root and rebuild the result
   --  rows / grid items. Synchronous -- the window blocks briefly while it runs.
   procedure Run_Search is
      Builder : Search.Queries.Query_Builder := Search.Queries.New_Builder;
      Token   : aliased Search.Engine.Cancellation_Token;
      Summary : Search.Engine.Execution_Summary;
      Results : Search.Types.Result_Vectors.Vector;

      procedure Collect (Batch : Search.Types.Result_Batch) is
      begin
         for Result of Batch.Results loop
            Results.Append (Result);
         end loop;
      end Collect;
   begin
      if Length (Query) = 0 then
         return;
      end if;

      Search.Queries.Add_Root (Builder, Root);
      Search.Queries.Set_Pattern (Builder, To_String (Query));
      Search.Queries.Set_Mode (Builder, Search.Types.Combined_Mode);
      Summary :=
        Search.Engine.Execute
          (Search.Queries.Build (Builder), Token'Access, Collect'Access);
      pragma Unreferenced (Summary);

      Rows := Search_GUI.To_Rows (Results);
      Grid_Items := Search_GUI.To_Grid_Items (Rows);
      Selected := (if Natural (Rows.Length) > 0 then 1 else 0);
   end Run_Search;

   --  Render one frame: the query field with its text, then the result list.
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
           (Width => W, Height => H, Line_Height => Line_Height, others => 0);
         Glyphs  : Guikit.Draw.Text_Render_Result;
         Batch   : Guikit.Vulkan.Submission_Batch;
      begin
         --  Query field.
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

         --  Result list, laid out by the grid from the Search_GUI items.
         declare
            Content_Y : constant Natural := Margin + Field_H + Margin;
            Content_H : constant Natural := (if H > Content_Y then H - Content_Y else 0);
            Columns   : Guikit.Item_Grid.Detail_Column_Bounds :=
              [others => (X => 0, Width => 0)];
            Layouts   : Guikit.Item_Grid.Item_Layout_Vectors.Vector;
         begin
            Columns (Guikit.Item_Grid.Name_Column) := (X => Margin, Width => Field_W);
            Layouts :=
              Guikit.Item_Grid.Calculate_Layout
                (Items         => Grid_Items,
                 View          => Guikit.Item_Grid.Details,
                 Content_X     => Margin,
                 Content_Y     => Content_Y,
                 Content_W     => Field_W,
                 Content_H     => Content_H,
                 Columns       => Columns,
                 Scroll_Pixels => 0,
                 Line_Height   => Line_Height);

            for I in 1 .. Natural (Layouts.Length) loop
               declare
                  L : constant Guikit.Item_Grid.Item_Layout := Layouts (I);
               begin
                  if L.Height > 0 then
                     Guikit.Item_Grid.Draw_Item_Background
                       (Rectangles      => Rects,
                        Clip_Width      => W,
                        Clip_Height     => H,
                        Cell            => L,
                        Kind            =>
                          (if I = Selected then Guikit.Item_Grid.Selected
                           else Guikit.Item_Grid.Alternate),
                        Selection_Color => Guikit.Draw.Selection_Color,
                        Hover_Color     => Guikit.Draw.Hover_Color,
                        Border_Color    => Guikit.Draw.Border_Color,
                        Alternate_Color => Guikit.Draw.Alternate_Row_Color);
                     Guikit.Item_Grid.Draw_Fitted_Text
                       (Text_Commands => Texts,
                        Clip_Width    => W,
                        Clip_Height   => H,
                        X             => L.Name_X,
                        Y             => L.Text_Y,
                        Width         => L.Name_Width,
                        Height        => Line_Height,
                        Text          => Grid_Items (I).Label,
                        Color         => Guikit.Draw.Text_Color,
                        Line_Height   => Line_Height);
                  end if;
               end;
            end loop;
         end;

         Glyphs := Guikit.Text.Build_Glyphs (Txt, Texts, No_Overlay_Tx);
         Batch  :=
           Guikit.Vulkan.Build_Submission
             (Rects, No_Tri, No_Icons, No_Overlay, Metrics,
              Guikit.Draw.Theme_Dark, Glyphs);
         Ignore_St :=
           Guikit.Vulkan.Present_Frame (Vk, Batch, Natural (Frame_W), Natural (Frame_H));
      end;
   end Draw_Frame;

   --  Enable framebuffer readback, render a few frames, and confirm the window,
   --  query field, and results region each hold ink.
   function Smoke_Passes return Boolean is
      Frame_W, Frame_H : Glfw.Size;
   begin
      Guikit.Vulkan.Set_Readback_Enabled (Vulkan, True);
      for I in 1 .. 6 loop
         Draw_Frame (Handle, Vulkan, Text);
      end loop;

      Glfw.Windows.Get_Framebuffer_Size (As_Window (Handle), Frame_W, Frame_H);
      declare
         FW : constant Natural := Natural (Frame_W);
         FH : constant Natural := Natural (Frame_H);
         Overall : constant Boolean :=
           Guikit.Vulkan.Readback_Region_Has_Ink (Vulkan, 0, 0, FW, FH, 0.003);
         Field   : constant Boolean :=
           Guikit.Vulkan.Readback_Region_Has_Ink (Vulkan, 0, FH / 40, FW, FH / 8, 0.001);
         Results : constant Boolean :=
           Guikit.Vulkan.Readback_Region_Has_Ink (Vulkan, 0, FH / 4, FW, FH / 2, 0.001);
      begin
         Ada.Text_IO.Put_Line
           ("search-desktop smoke: overall=" & Boolean'Image (Overall)
            & " field=" & Boolean'Image (Field)
            & " results=" & Boolean'Image (Results)
            & " rows=" & Natural'Image (Natural (Rows.Length)));
         return Overall and then Field and then Results;
      end;
   end Smoke_Passes;

begin
   --  Load the fonts: guikit's chain (Guikit.Fonts) in the host's font folders
   --  (Search.Fonts). With no font there is nothing to draw text with: say so
   --  and fail, rather than vanish -- a --smoke run that exits 0 here would
   --  pass without rendering anything.
   declare
      Primary : constant String := Search.Fonts.Primary;
   begin
      if Primary = "" then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "search-desktop: no usable font was found");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      Ignore_Ts :=
        Guikit.Text.Initialize
          (Text, Primary, Search.Fonts.Fallbacks,
           --  Sized from the line height, as files does: the font at four
           --  fifths of it, the cell at the advance guikit's widgets measure
           --  labels and carets with.
           Pixel_Size   => Line_Height * 4 / 5,
           Cell_Width   => Guikit.Layout.Caret_Advance_Width (Line_Height),
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

   if Smoke then
      Query := To_Unbounded_String (Smoke_Pattern);
      Run_Search;
      if Smoke_Passes then
         Ada.Text_IO.Put_Line ("search-desktop smoke: PASS");
      else
         Ada.Text_IO.Put_Line ("search-desktop smoke: FAIL");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
      return;
   end if;

   --  Main loop. Event-driven: block until an event (with a 1s defensive cap),
   --  then apply pending input and redraw only when something changed.
   while not Glfw.Windows.Should_Close (As_Window (Handle)) loop
      Guikit.Vulkan.Wait_For_Events (1.0);
      Guikit.Vulkan.Poll_Events;

      --  The input in the order it came: a Backspace typed between two
      --  letters deletes the first of them, and Enter searches for what was
      --  typed before it.
      declare
         use type Glfw.Input.Keys.Key;
         use type Guikit.Input.Pending.Event_Kind;
         Item  : Guikit.Input.Pending.Event;
         Taken : Boolean;
      begin
         loop
            Handle.Take (Item, Taken);
            exit when not Taken;
            if Item.Kind = Guikit.Input.Pending.Character_Input then
               Append (Query, Guikit.Utf8.Encode (Item.Code));
            elsif Item.Kind = Guikit.Input.Pending.Key_Input then
               if Item.Key = Glfw.Input.Keys.Escape then
                  Quit := True;
               elsif Item.Key = Glfw.Input.Keys.Enter or else Item.Key = Glfw.Input.Keys.Numpad_Enter then
                  Run_Search;
               elsif Item.Key = Glfw.Input.Keys.Backspace then
                  Backspace (Query);
               elsif Item.Key = Glfw.Input.Keys.Up then
                  if Selected > 1 then
                     Selected := Selected - 1;
                  end if;
               elsif Item.Key = Glfw.Input.Keys.Down then
                  if Selected < Natural (Rows.Length) then
                     Selected := Selected + 1;
                  end if;
               end if;
            end if;
         end loop;
      end;

      exit when Quit;

      declare
         Frame_W, Frame_H : Glfw.Size;
      begin
         --  A resize is not delivered through the input callbacks, so detect it
         --  here and mark dirty; otherwise the resized window would not repaint.
         Glfw.Windows.Get_Framebuffer_Size (As_Window (Handle), Frame_W, Frame_H);
         if Natural (Frame_W) /= Natural (Last_Frame_W)
           or else Natural (Frame_H) /= Natural (Last_Frame_H)
         then
            Handle.Mark_Dirty;
            Last_Frame_W := Frame_W;
            Last_Frame_H := Frame_H;
         end if;

         --  Redraw only when something changed; otherwise the identical frame is
         --  already on screen and the build/submit/present path is skipped.
         if Handle.Dirty or else Guikit.Vulkan.Readback_Enabled (Vulkan) then
            Draw_Frame (Handle, Vulkan, Text);
            Handle.Clear_Dirty;
         end if;
      end;
   end loop;
end Search.Desktop;

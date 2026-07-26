with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with GNAT.OS_Lib;

with Regexp;
with Version.Ignore;

with Search.Content;

package body Search.Engine is
   use type Ada.Directories.File_Kind;
   use type Search.Types.Text_Mode;
   use type Search.Types.Hidden_Policy;
   use type Search.Types.Completion_State;
   use type Regexp.Match_Status;

   protected body Cancellation_Token is
      procedure Cancel is
      begin
         Flag := True;
      end Cancel;

      function Cancelled return Boolean is (Flag);
   end Cancellation_Token;

   function Lower (Text : String) return String is
      Result : String (Text'Range);
   begin
      for I in Text'Range loop
         Result (I) := Ada.Characters.Handling.To_Lower (Text (I));
      end loop;
      return Result;
   end Lower;

   function Base_Name (Path : String) return String is
   begin
      return Ada.Directories.Simple_Name (Path);
   exception
      when others =>
         return Path;
   end Base_Name;

   function Relative_To (Root : String; Path : String) return String is
   begin
      if Path'Length >= Root'Length and then Path (Path'First .. Path'First + Root'Length - 1) = Root then
         if Path'Length = Root'Length then
            return "";
         elsif Path (Path'First + Root'Length) = GNAT.OS_Lib.Directory_Separator then
            return Path (Path'First + Root'Length + 1 .. Path'Last);
         else
            return Path;
         end if;
      end if;
      return Path;
   end Relative_To;

   function Is_Hidden (Path : String) return Boolean is
      Name : constant String := Base_Name (Path);
   begin
      return Name'Length > 0 and then Name (Name'First) = '.';
   end Is_Hidden;

   function Text_Matches
     (Text  : String;
      Query : Search.Queries.Query;
      Regex : Regexp.Compile_Result) return Boolean
   is
      Hay    : constant String := (if Search.Queries.Case_Sensitive (Query) then Text else Lower (Text));
      Needle : constant String :=
        (if Search.Queries.Case_Sensitive (Query)
         then Search.Queries.Pattern (Query)
         else Lower (Search.Queries.Pattern (Query)));
   begin
      if Search.Queries.Text_Mode (Query) = Search.Types.Regular_Expression then
         return Regexp.Find_First
           (Regex.Expression,
            Text,
            (Case_Sensitive => Search.Queries.Case_Sensitive (Query), others => <>)).Status = Regexp.Match_Ok;
      else
         return Ada.Strings.Fixed.Index (Hay, Needle) > 0;
      end if;
   end Text_Matches;

   procedure Flush
     (Batch    : in out Search.Types.Result_Batch;
      On_Batch : access procedure (Batch : Search.Types.Result_Batch);
      Final    : Boolean := False)
   is
   begin
      Batch.Final := Final;
      if On_Batch /= null and then (Final or else not Batch.Results.Is_Empty or else not Batch.Diagnostics.Is_Empty) then
         On_Batch.all (Batch);
      end if;
      Batch.Sequence := Batch.Sequence + 1;
      Batch.Results.Clear;
      Batch.Diagnostics.Clear;
      Batch.Final := False;
   end Flush;

   function Execute
     (Query      : Search.Queries.Query;
      Token      : access Cancellation_Token;
      On_Batch   : access procedure (Batch : Search.Types.Result_Batch) := null;
      Batch_Size : Positive := 64) return Execution_Summary
   is
      Summary : Execution_Summary := (State => Search.Types.Completed, others => <>);
      Batch   : Search.Types.Result_Batch;
      Next_Id : Natural := 0;
      Regex   : Regexp.Compile_Result;

      procedure Add_Diagnostic (Diagnostic : Search.Types.Diagnostic) is
      begin
         Summary.Diagnostics.Append (Diagnostic);
         Batch.Diagnostics.Append (Diagnostic);
      end Add_Diagnostic;

      procedure Add_Result (Item : Search.Types.Search_Result) is
      begin
         Summary.Result_Count := Summary.Result_Count + 1;
         Batch.Results.Append (Item);
         if Natural (Batch.Results.Length) >= Batch_Size then
            Flush (Batch, On_Batch);
         end if;
      end Add_Result;

      procedure Visit (Root : String; Rules : Standard.Version.Ignore.Ignore_Rules; Path : String; Depth : Natural) is
         Search_Handle : Ada.Directories.Search_Type;
         Dir_Entry         : Ada.Directories.Directory_Entry_Type;
         Kind          : Ada.Directories.File_Kind;
         Rel           : constant String := Relative_To (Root, Path);
         Ignored       : Standard.Version.Ignore.Match_Result;
         Name_Match    : Boolean := False;
         Path_Match    : Boolean := False;
         Content       : Search.Content.Scan_Result;
      begin
         if Token /= null and then Token.Cancelled then
            Summary.State := Search.Types.Cancelled;
            return;
         end if;

         if Search.Queries.Hidden_Policy (Query) = Search.Types.Exclude_Hidden and then Is_Hidden (Path) then
            return;
         end if;

         if Search.Queries.Gitignore_Aware (Query) and then Rel'Length > 0 then
            Ignored := Standard.Version.Ignore.Match (Rules, Rel, Ada.Directories.Kind (Path) = Ada.Directories.Directory);
            if Ignored.Has_Match and then Ignored.Is_Ignored then
               return;
            end if;
         end if;

         Kind := Ada.Directories.Kind (Path);
         if Kind = Ada.Directories.Ordinary_File or else Kind = Ada.Directories.Directory then
            if Search.Queries.Mode (Query) in Search.Types.Filename_Mode | Search.Types.Combined_Mode then
               Name_Match := Text_Matches (Base_Name (Path), Query, Regex);
            end if;
            if Search.Queries.Mode (Query) in Search.Types.Path_Mode | Search.Types.Combined_Mode then
               Path_Match := Text_Matches (Path, Query, Regex);
            end if;

            if Kind = Ada.Directories.Ordinary_File
              and then Search.Queries.Mode (Query) in Search.Types.Content_Mode | Search.Types.Combined_Mode
            then
               Content := Search.Content.Scan_File (Path, Query);
            end if;

            if Name_Match or else Path_Match or else Content.Match_Count > 0 then
               Next_Id := Next_Id + 1;
               Add_Result
                 ((Id           => Next_Id,
                   Root         => To_Unbounded_String (Root),
                   Path         => To_Unbounded_String (Path),
                   Name         => To_Unbounded_String (Base_Name (Path)),
                   Size         => (if Kind = Ada.Directories.Ordinary_File
                                    then Long_Long_Integer (Ada.Directories.Size (Path))
                                    else 0),
                   Is_Directory => Kind = Ada.Directories.Directory,
                   Match_Count  => Natural'Max (1, Content.Match_Count),
                   Matches      => Content.Matches,
                   Freshness    => Search.Types.Fresh,
                   Revision     => 1,
                   Diagnostics  => Content.Diagnostics));
            end if;
         end if;

         if Kind = Ada.Directories.Directory
           and then Search.Queries.Recursive (Query)
           and then (Search.Queries.Max_Depth (Query) = 0 or else Depth < Search.Queries.Max_Depth (Query))
         then
            Ada.Directories.Start_Search
              (Search    => Search_Handle,
               Directory => Path,
               Pattern   => "",
               Filter    => [Ada.Directories.Ordinary_File => True,
                             Ada.Directories.Directory     => True,
                             Ada.Directories.Special_File  => False]);
            while Ada.Directories.More_Entries (Search_Handle) loop
               Ada.Directories.Get_Next_Entry (Search_Handle, Dir_Entry);
               declare
                  Child_Name : constant String := Ada.Directories.Simple_Name (Dir_Entry);
               begin
                  if Child_Name /= "." and then Child_Name /= ".." then
                     Visit (Root, Rules, Ada.Directories.Full_Name (Dir_Entry), Depth + 1);
                  end if;
               end;
               exit when Summary.State = Search.Types.Cancelled;
            end loop;
            Ada.Directories.End_Search (Search_Handle);
         end if;
      exception
         when others =>
            if Ada.Directories.More_Entries (Search_Handle) then
               Ada.Directories.End_Search (Search_Handle);
            end if;
            Add_Diagnostic
              ((Severity => Search.Types.Warning,
                Code     => To_Unbounded_String ("traversal.entry.failed"),
                Path     => To_Unbounded_String (Path),
                Message  => To_Unbounded_String ("traversal.entry.failed")));
      end Visit;

      task type Traversal_Worker is
         entry Run;
      end Traversal_Worker;

      task body Traversal_Worker is
      begin
         --  The whole traversal runs inside the rendezvous so that the caller's
         --  Worker.Run only returns once Summary is fully populated. A separate
         --  task may still cancel mid-traversal through the shared Token.
         accept Run do
            declare
               Diagnostics : constant Search.Types.Diagnostic_Vectors.Vector := Search.Queries.Validate (Query);
            begin
               if not Diagnostics.Is_Empty then
                  Summary.State := Search.Types.Failed;
                  for Diagnostic of Diagnostics loop
                     Add_Diagnostic (Diagnostic);
                  end loop;
               else
                  if Search.Queries.Text_Mode (Query) = Search.Types.Regular_Expression then
                     Regex := Regexp.Compile (Search.Queries.Pattern (Query));
                  else
                     Regex := Regexp.Compile_Literal (Search.Queries.Pattern (Query));
                  end if;

                  for Root of Search.Queries.Roots (Query) loop
                     declare
                        Root_Text : constant String := To_String (Root);
                        Rules     : constant Standard.Version.Ignore.Ignore_Rules :=
                          Standard.Version.Ignore.Load (Root_Text);
                     begin
                        Visit (Root_Text, Rules, Root_Text, 0);
                     end;
                     exit when Summary.State = Search.Types.Cancelled;
                  end loop;
               end if;
            end;
         end Run;
      end Traversal_Worker;

      Worker : Traversal_Worker;
   begin
      Worker.Run;
      Flush (Batch, On_Batch, Final => True);
      return Summary;
   end Execute;
end Search.Engine;

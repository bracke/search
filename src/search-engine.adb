with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with GNAT.OS_Lib;

with Hostkit.Fs;
with Hostkit.Path_Text;

with Regexp;
with Version.Ignore;

with Search.Content;
with Search.Text_Fold;

package body Search.Engine is
   use type Ada.Directories.File_Kind;
   use type Search.Types.Text_Mode;
   use type Search.Types.Hidden_Policy;
   use type Search.Types.Completion_State;
   use type Search.Types.Symlink_Policy;
   use type Regexp.Match_Status;

   package Path_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   protected body Cancellation_Token is
      procedure Cancel is
      begin
         Flag := True;
      end Cancel;

      function Cancelled return Boolean is (Flag);
   end Cancellation_Token;

   function Base_Name (Path : String) return String is
   begin
      return Ada.Directories.Simple_Name (Path);
   exception
      when others =>
         return Path;
   end Base_Name;

   function Is_Hidden (Path : String) return Boolean is
      Name : constant String := Base_Name (Path);
   begin
      return Name'Length > 0 and then Name (Name'First) = '.';
   end Is_Hidden;

   --  Whether Text matches the query. Needle is the literal pattern as it is
   --  matched -- folded once per query when matching ignores case -- so the
   --  pattern is not folded again for every name, path and line.
   function Text_Matches
     (Text   : String;
      Query  : Search.Queries.Query;
      Regex  : Regexp.Compile_Result;
      Needle : String) return Boolean
   is
   begin
      if Search.Queries.Text_Mode (Query) = Search.Types.Regular_Expression then
         --  A code point at a time, as content is scanned, so "." and a class
         --  take a whole "é" in a name. A name that is not UTF-8 (POSIX lets
         --  a name be any bytes) is matched a byte at a time: in UTF-8 mode
         --  the matcher would refuse it outright.
         return Regexp.Find_First
           (Regex.Expression,
            Text,
            (Case_Sensitive => Search.Queries.Case_Sensitive (Query),
             Character_Mode =>
               (if Regexp.Validate_UTF_8 (Text).Valid then Regexp.UTF_8_Mode else Regexp.ASCII_Mode),
             others         => <>)).Status = Regexp.Match_Ok;
      elsif Search.Queries.Case_Sensitive (Query) then
         return Ada.Strings.Fixed.Index (Text, Needle) > 0;
      else
         return Ada.Strings.Fixed.Index (Search.Text_Fold.Fold (Text), Needle) > 0;
      end if;
   end Text_Matches;

   procedure Flush
     (Batch    : in out Search.Types.Result_Batch;
      On_Batch : access procedure (Batch : Search.Types.Result_Batch);
      Final    : Boolean := False)
   is
   begin
      Batch.Final := Final;
      if On_Batch /= null
        and then (Final or else not Batch.Results.Is_Empty or else not Batch.Diagnostics.Is_Empty)
      then
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
      Policy  : constant Search.Types.Symlink_Policy := Search.Queries.Symlink_Policy (Query);
      --  The pattern as literal matching compares it: folded here, once.
      Needle  : constant String :=
        (if Search.Queries.Case_Sensitive (Query)
         then Search.Queries.Pattern (Query)
         else Search.Text_Fold.Fold (Search.Queries.Pattern (Query)));
      --  The directories walked so far, by their resolved path: a link back
      --  up the tree (a loop), a folder walked already through a link, and a
      --  root inside another root are then not walked again.
      Walked  : Path_Sets.Set;
      --  The objects reported so far, by Identity: overlapping roots, or a
      --  folder met both directly and through a link, report each once.
      Reported : Path_Sets.Set;

      --  Whether the directory at Path is to be walked now.
      --
      --  @param Real Its resolved path, "" when that could not be had.
      --  @param Is_Link Whether Path is a link met in the walk.
      function First_Walk (Real : String; Is_Link : Boolean) return Boolean is
      begin
         if Real = "" then
            --  Unresolvable: a plain folder is walked; a link, which might
            --  lead anywhere, is not.
            return not Is_Link;
         elsif Walked.Contains (Real) then
            return False;
         end if;
         Walked.Insert (Real);
         return True;
      end First_Walk;

      --  What an object is, whatever root it was reached from: its folder's
      --  resolved path and its own name. The last component is not resolved,
      --  so a link is an object of its own and not the thing it points to.
      --  A root that is not a link is its own resolved path.
      function Identity_Of_Root (Path : String) return String is
         Parent : constant String := Hostkit.Path_Text.Parent (Path);
         Leaf   : constant String := Hostkit.Path_Text.Leaf (Path);
      begin
         if Parent = "" or else Leaf = "" or else not Hostkit.Fs.Is_Link (Path) then
            declare
               Real : constant String := Hostkit.Fs.Real_Path (Path);
            begin
               return (if Real = "" then Path else Real);
            end;
         end if;
         declare
            Real_Parent : constant String := Hostkit.Fs.Real_Path (Parent);
         begin
            return Hostkit.Fs.Join ((if Real_Parent = "" then Parent else Real_Parent), Leaf);
         end;
      end Identity_Of_Root;

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

      --  Walk the folder at Path, Rel below Root, once: its entries are
      --  visited one level down. Propagates what stops the walk, for Visit
      --  to report.
      procedure Walk_Children
        (Root    : String;
         Rules   : Standard.Version.Ignore.Ignore_Rules;
         Path    : String;
         Rel     : String;
         Is_Link : Boolean;
         Depth   : Natural);

      --  Visit the object at Path, Rel below Root ("" for the root itself),
      --  known as Identity (see Identity_Of_Root), Depth folders down.
      procedure Visit
        (Root     : String;
         Rules    : Standard.Version.Ignore.Ignore_Rules;
         Path     : String;
         Rel      : String;
         Identity : String;
         Depth    : Natural)
      is
         Kind          : Ada.Directories.File_Kind;
         Ignored       : Standard.Version.Ignore.Match_Result;
         Name_Match    : Boolean := False;
         Path_Match    : Boolean := False;
         Content       : Search.Content.Scan_Result;
         --  A link met in the walk (a root is walked whatever it is: it was
         --  named). Ada.Directories.Kind follows links, so a link to a folder
         --  reads as a folder; whether to go through it is the query's
         --  Symlink_Policy.
         Is_Link       : constant Boolean := Depth > 0 and then Hostkit.Fs.Is_Link (Path);
      begin
         if Token /= null and then Token.Cancelled then
            Summary.State := Search.Types.Cancelled;
            return;
         end if;

         --  A root is searched whatever its name: "." (the current folder) or
         --  a hidden folder the user named is what they asked for.
         if Depth > 0
           and then Search.Queries.Hidden_Policy (Query) = Search.Types.Exclude_Hidden
           and then Is_Hidden (Path)
         then
            return;
         end if;

         --  Resolve the node's kind once: the gitignore test and the match logic
         --  below both need it, and Ada.Directories.Kind is a stat -- previously
         --  a gitignore-aware walk paid for two stats of the same path per node.
         Kind := Ada.Directories.Kind (Path);

         if Search.Queries.Gitignore_Aware (Query) and then Rel'Length > 0 then
            Ignored := Standard.Version.Ignore.Match (Rules, Rel, Kind = Ada.Directories.Directory);
            if Ignored.Has_Match and then Ignored.Is_Ignored then
               return;
            end if;
         end if;
         if Kind = Ada.Directories.Ordinary_File or else Kind = Ada.Directories.Directory then
            if Search.Queries.Mode (Query) in Search.Types.Filename_Mode | Search.Types.Combined_Mode then
               Name_Match := Text_Matches (Base_Name (Path), Query, Regex, Needle);
            end if;
            --  The path below the root, not the root's own: searching
            --  ~/notes for "notes" by path is a search inside it, and the
            --  root's name is in every path there.
            if Search.Queries.Mode (Query) in Search.Types.Path_Mode | Search.Types.Combined_Mode
              and then Rel'Length > 0
            then
               Path_Match := Text_Matches (Rel, Query, Regex, Needle);
            end if;

            --  A link to a file is read only when the policy follows links to
            --  files; otherwise it is an entry of its own, found by name and path.
            if Kind = Ada.Directories.Ordinary_File
              and then Search.Queries.Mode (Query) in Search.Types.Content_Mode | Search.Types.Combined_Mode
              and then (not Is_Link or else Policy /= Search.Types.Do_Not_Follow_Symlinks)
            then
               Content := Search.Content.Scan_File (Path, Query, Needle, Regex);
            end if;

            if (Name_Match or else Path_Match or else Content.Match_Count > 0)
              and then not Reported.Contains (Identity)
            then
               Reported.Insert (Identity);
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

         --  A link to a folder is gone through only when the policy follows all
         --  links, and every folder is walked once (First_Walk): following
         --  links blindly recursed without end round a link loop and walked a
         --  linked tree inside the root twice, and a root inside another root
         --  was walked under both.
         if Kind = Ada.Directories.Directory
           and then Search.Queries.Recursive (Query)
           and then (Search.Queries.Max_Depth (Query) = 0 or else Depth < Search.Queries.Max_Depth (Query))
           and then (not Is_Link or else Policy = Search.Types.Follow_All_Symlinks)
         then
            Walk_Children (Root, Rules, Path, Rel, Is_Link, Depth);
         end if;
      exception
         when others =>
            --  A root that cannot be walked fails the search's promise for
            --  it, which is an error; an entry below it is a warning.
            declare
               Code : constant String := (if Depth = 0 then "traversal.root.failed" else "traversal.entry.failed");
            begin
               Add_Diagnostic
                 ((Severity => (if Depth = 0 then Search.Types.Error else Search.Types.Warning),
                   Code     => To_Unbounded_String (Code),
                   Path     => To_Unbounded_String (Path),
                   Message  => To_Unbounded_String (Code)));
            end;
      end Visit;

      procedure Walk_Children
        (Root    : String;
         Rules   : Standard.Version.Ignore.Ignore_Rules;
         Path    : String;
         Rel     : String;
         Is_Link : Boolean;
         Depth   : Natural)
      is
         Real          : constant String := Hostkit.Fs.Real_Path (Path);
         --  The folder its entries are named in, for their identities.
         Folder        : constant String := (if Real = "" then Path else Real);
         Search_Handle : Ada.Directories.Search_Type;
         Dir_Entry     : Ada.Directories.Directory_Entry_Type;
      begin
         if First_Walk (Real, Is_Link) then
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
                     Visit
                       (Root     => Root,
                        Rules    => Rules,
                        Path     => Ada.Directories.Full_Name (Dir_Entry),
                        Rel      =>
                          (if Rel = "" then Child_Name else Rel & GNAT.OS_Lib.Directory_Separator & Child_Name),
                        Identity => Hostkit.Fs.Join (Folder, Child_Name),
                        Depth    => Depth + 1);
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
            raise;
      end Walk_Children;

      --  Search the root at Root_Text, absolute. A root whose ignore rules
      --  cannot be read cannot be walked either, and is reported as such.
      procedure Walk_Root (Root_Text : String) is
         Rules : Standard.Version.Ignore.Ignore_Rules;
      begin
         begin
            Rules := Standard.Version.Ignore.Load (Root_Text);
         exception
            when others =>
               Add_Diagnostic
                 ((Severity => Search.Types.Error,
                   Code     => To_Unbounded_String ("traversal.root.failed"),
                   Path     => To_Unbounded_String (Root_Text),
                   Message  => To_Unbounded_String ("traversal.root.failed")));
               return;
         end;
         Visit
           (Root     => Root_Text,
            Rules    => Rules,
            Path     => Root_Text,
            Rel      => "",
            Identity => Identity_Of_Root (Root_Text),
            Depth    => 0);
      end Walk_Root;

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
                     Regex := Regexp.Compile (Search.Queries.Pattern (Query), Character_Mode => Regexp.UTF_8_Mode);
                  else
                     Regex := Regexp.Compile_Literal (Search.Queries.Pattern (Query));
                  end if;

                  for Root of Search.Queries.Roots (Query) loop
                     --  Absolute, so every path below it is read from it,
                     --  and a relative root from the query's base folder.
                     Walk_Root (Search.Queries.Resolved_Root (Query, To_String (Root)));
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

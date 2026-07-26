with Ada.Command_Line;

with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;

with Search_Tests.Suite;

--  Test_Runner exits zero whatever happens, so a failing test would report
--  success and "alr test" would be green over it. Report the status, so a
--  failure is a failure.
procedure Run_Tests is
   use type AUnit.Status;

   function Runner is new AUnit.Run.Test_Runner_With_Status (Search_Tests.Suite.Suite);

   Reporter : AUnit.Reporter.Text.Text_Reporter;
   Status   : AUnit.Status;
begin
   Status := Runner (Reporter);
   if Status = AUnit.Failure then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Run_Tests;

with Search.Queries;
with Search.Types;

package Search.Engine is
   protected type Cancellation_Token is
      procedure Cancel;
      function Cancelled return Boolean;
   private
      Flag : Boolean := False;
   end Cancellation_Token;

   type Execution_Summary is record
      State       : Search.Types.Completion_State := Search.Types.Not_Started;
      Result_Count : Natural := 0;
      Diagnostics : Search.Types.Diagnostic_Vectors.Vector;
   end record;

   function Execute
     (Query      : Search.Queries.Query;
      Token      : access Cancellation_Token;
      On_Batch   : access procedure (Batch : Search.Types.Result_Batch) := null;
      Batch_Size : Positive := 64) return Execution_Summary;
end Search.Engine;

with AUnit.Test_Cases;

--  Content scanning (Search.Content): long lines, the file-size limit, binary
--  detection, UTF-16 decoding and match previews.
package Search_Tests.Content_Tests is
   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;
   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);
end Search_Tests.Content_Tests;

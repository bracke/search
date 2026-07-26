with Search.Types;

package Search.Exports is
   function Render
     (Results : Search.Types.Result_Vectors.Vector;
      Format  : Search.Types.Export_Format) return String;
end Search.Exports;

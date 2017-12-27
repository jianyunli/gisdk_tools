/*
This is a simple text file parser that runs through every .rsc file in a
directory (and subdirectories) and pulls out macro names into a markdown file.
Hopefully, it can be built into something more in the future.
*/

Macro "docstrings" (dir)

  out_file = OpenFile(dir + "/macros.md", "w")
  WriteLine(out_file, "*This file created by docstrings.rsc in GT*")

  a_files = RunMacro("Catalog Files", dir, "rsc")
  for f in a_files do
    {drive, directory, name, ext} = SplitPath(f)

    WriteLine(out_file, "")
    WriteLine(out_file, "## " + name + ext)

    file = OpenFile(f, "r")
    while not FileAtEOF(file) do
      line = Trim(ReadLine(file))
      check_macro = Lower(Left(line, 7))
      check_dbox = Lower(Left(line, 6))
      if check_macro = "macro \"" or check_dbox = "dbox \"" then do
        sub = ParseString(line, "\"")
        WriteLine(out_file, "  * " + sub[2] + "  ")
      end
    end
    CloseFile(file)
  end
  CloseFile(out_file)
  ShowMessage("Done")
EndMacro

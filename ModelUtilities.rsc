/*
This script provides a library of tools that are generally useful when
running GISDK models.
*/

/*
This macro clears the workspace.
It also cleans up DCC files created from csv tables.
*/

Macro "Close All"

  // Close maps
  maps = GetMapNames()
  if maps <> null then do
    for i = 1 to maps.length do
      CloseMap(maps[i])
    end
  end

  // Close any views
  RunMacro("TCB Init")
  RunMacro("G30 File Close All")

  // Close matrices
  mtxs = GetMatrices()
  if mtxs <> null then do
    handles = mtxs[1]
    for i = 1 to handles.length do
      handles[i] = null
    end
  end

  // Delete any DCC files in the scenario folder
  // This requires the global variable MODELARGS be established in
  // your project code, but will simply do nothing if it doesn't exist.
  if MODELARGS.scen_dir <> null then do
    a_files = RunMacro("Catalog Files", MODELARGS.scen_dir, {"DCC"})
    for f = 1 to a_files.length do
      DeleteFile(a_files[f])
    end
  end
endMacro

/*
Removes any progress bars open
TC does not have a function to get all open progress bars.
As a result, keep calling DestroyProgressBar() until you
hit an error (meaning they are all closed).
*/

Macro "Destroy Progress Bars"
  on notfound goto quit
  while 0 < 1 do
    DestroyProgressBar()
  end
  quit:
  on notfound default
EndMacro

/*
Similar to Destroy Progress Bars, but the name of the stopwatch
is required.  Thus, any stopwatches used in the model must
be added by name to this list.
*/

Macro "Destroy Stopwatches"
  on notfound goto quit
  DestroyStopwatch("run_time")
  quit:
  on notfound default
EndMacro

/*
Checks the UI date against the rsc/lst files used to create it.  If any of the
rsc files are newer than the UI, the UI should be recompiled.

Inputs:
ui_dbd       complete path to the UI file
scriptDir   path to folder containing RSC files

Returns:
Shows a warning message if the UI is out of date.
*/

Macro "Recompile UI?" (ui_dbd, scriptDir)

  a_files = RunMacro("Catalog Files", scriptDir, {"rsc", "lst"})
  // Check the *.1 file instead of *.dbd.
  // The .dbd file doesn't get updated on recompile.
  a_uiInfo = GetFileInfo(Substitute(ui_dbd, ".dbd", ".1", ))
  uiTime = a_uiInfo[9]
  a_units = {"year", "month", "day", "hour", "minute", "second", "millisecond"}
  recompile = "False"
  for i = 1 to a_files.length do
    file = a_files[i]

    a_info = GetDirectoryInfo(file, "File")
    fileTime = a_info[1][9]
    for j = 1 to a_units.length do
      unit = a_units[j]
      uT = uiTime.(unit)
      fT = fileTime.(unit)

      // If the year is greater in the UI than rsc, no problem.
      // Don't check any more date units on the current file.
      if uiTime.(unit) > fileTime.(unit) then do
        j = a_units.length + 1
      end

      // If the year is less in UI than rsc, then there is a problem.
      // Don't check any more date units OR files.
      if uiTime.(unit) < fileTime.(unit) then do
        recompile = "True"
        problemFile = file
        j = a_units.length + 1
        i = a_files.length + 1
      end

      // Otherwise, the years are the same, and the j loop must continue to
      // compare the months (then days, hours, etc.)
    end
  end

  // Show warning if necessary
  if recompile then ShowMessage("The compiled UI is older than " +
    problemFile + "\n(and possibly other .rsc files)\nRe-compile the UI " +
    "before using the model.")
EndMacro


/*
Reads a settings file that contains scenario-specific information.  The file can
have multiple dimensions.  For example, a time-of-day file might have pupose
and time period (e.g. "HBW" and "AM").  The dimension fields must be the first
fields in the file.

Input:
parameterFile:  Must meet the following criteria:
  - Be CSV format
  - Begin with dimension field(s)
    e.g. "Parameter" for 1D
    e.g. "Purpose" and "TOD" for 2D
  - End with the following two fields:
    - Value
    - Description

incDescr:   Boolean   "Include Description"
                      Whether or not the description will be included.
                      For reading and writing to settings csv files, this should
                      be true to preserve the description information.
                      Defaults to "False".
                      Parameter table must always have a Description field.

Output:
Settings    Array     Options array that holds all parameters
*/

Macro "Read Parameter File" (parameterFile, incDescr)

  // Set default value of optional variables
  if incDescr = null then incDescr = "False"

  // Error checking
  if parameterFile = null then Throw("No settings file provided.")

  // Open the parameter table and get separate arrays of dimension fields
  // and value/description fields.
  tbl = OpenTable("tbl", "CSV", {parameterFile, })
  a_fieldnames = GetFields(tbl, "All")
  if a_fieldnames = null then Throw("Parameter file is empty\n" + parameterFile)
  a_fieldnames = a_fieldnames[1]
  value_pos = ArrayPosition(a_fieldnames, {"Value"}, )
  dimensions = value_pos - 1
  a_dFields = SubArray(a_fieldnames, 1, dimensions)
  a_vFields = {"Value", "Description"}

  // Get data vectors
  a_dVecs = GetDataVectors(tbl + "|", a_dFields, )
  {v_value, v_desc} = GetDataVectors(tbl + "|", a_vFields, )

  // Close view
  CloseView(tbl)
  DeleteFile(Substitute(parameterFile, ".csv", ".DCC", ))

  if v_value.length = 0 then Throw(
    "No values found in parameter file.\n" +
    parameterFile
    )

  // Loop over each row of the parameter table
  for i = 1 to a_dVecs[1].length do
    a_path = null
    value = v_value[i]
    desc = v_desc[i]

    // If the value array is mixed strings and numerics, all will
    // be converted to strings.  Correct that here.
    // Convert any string-number into a number
    if TypeOf(value) = "string" then do
      value = if value = "0"
        then 0
        else if Value(value) = 0
          then value
          else Value(value)
    end

    // Create the path array. Check if any of the path components are null.
    null_path = "false"
    for d = 1 to dimensions do
      partial_path = a_dVecs[d][i]

      if partial_path = null then null_path = "true"
      a_path = a_path + {partial_path}
    end

    // if any of the path components for the current row were null,
    // skip the row. This allows for extra rows in the description column
    // that don't have to correspond to any variables.
    if !null_path then do
      if !incDescr then
        Parameters = RunMacro("Insert into Opts Array", Parameters, a_path, value)
      else do
        a_path2 = a_path + {"value"}
        Parameters = RunMacro("Insert into Opts Array", Parameters, a_path2, value)
        a_path2 = a_path + {"desc"}
        Parameters = RunMacro("Insert into Opts Array", Parameters, a_path2, desc)
      end
    end
  end

  Return(Parameters)
EndMacro

/*
Recursive macro used by "Read Parameter File"

Input:
OptsArray   Array   The options array in which to insert information.  If empty,
                    a new options array will be created.

path        Array   Names of the sub-arrays describing the location to insert.
                    e.g., {"HBW", "AM"} would create the following location:
                    OptsArray.HBW.AM

value               The value to be placed into the specified location

Output:
An options array with the value inserted into the specified location
*/

Macro "Insert into Opts Array" (OptsArray, path, value)

  location = path[1]
  if path.length > 1 then do
    path = ExcludeArrayElements(path, 1, 1)
    OptsArray.(location) = RunMacro(
      "Insert into Opts Array", OptsArray.(location), path, value
      )
  end else do
    OptsArray.(location) = value
  end

  return(OptsArray)
EndMacro

/*
Writes out an options array to a CSV file.

Input
Parameters      Array of parameters to write
parameterFile   File to write parameters out to
col_names        Array of column names.  Must end with "Value" and "Description".
*/

Macro "Write Parameter File" (Parameters, parameterFile, col_names)

  // Write column names
  file = OpenFile(parameterFile, "w")
  str = col_names[1]
  for i = 2 to col_names.length do
    str = str + "," + col_names[i]
  end
  WriteLine(file, str)

  RunMacro("Recursive OptsArray Writing", Parameters, string, file)

  CloseFile(file)
EndMacro

/*
Used by "Write Parameter File"
Recursively works through every level of an options array and writes a line.
Expects the bottom level of the options array to be made up of "value" and
"desc" values and includes both in the same line.
*/

Macro "Recursive OptsArray Writing" (OptsArray, string, file)

  for i = 1 to OptsArray.length do
    newOptsArray = OptsArray[i]

    test1 = newOptsArray[1]
    test2 = newOptsArray[2]

    if TypeOf(newOptsArray[2]) = "array" then do
      if string = null then newString = newOptsArray[1]
      else newString = string + "," + newOptsArray[1]

      RunMacro("Recursive OptsArray Writing", newOptsArray[2], newString, file)
    end else do

      value = OptsArray.value
      if TypeOf(value) <> "string" then value = String(value)
      desc = OptsArray.desc
      if TypeOf(desc) <> "string" then value = String(desc)

      newString = string + "," + value + "," + desc

      WriteLine(file, newString)
      return()
    end
  end

EndMacro

/*
Removes a field from a view/layer

Input
viewName  Name of view or layer (must be open)
field_name Name of the field to remove. Can pass string or array of strings.
*/

Macro "Drop Field" (viewName, field_name)
  a_str = GetTableStructure(viewName)

  if TypeOf(field_name) = "string" then field_name = {field_name}

  for fn = 1 to field_name.length do
    name = field_name[fn]

    for i = 1 to a_str.length do
      a_str[i] = a_str[i] + {a_str[i][1]}
      if a_str[i][1] = name then position = i
    end
    if position <> null then do
      a_str = ExcludeArrayElements(a_str, position, 1)
      ModifyTable(viewName, a_str)
    end
  end
EndMacro

/*
Recursively searches the directory and any subdirectories for files
unlike TransCADs "GetDirectoryInfo", which only searches top level.

This can be useful for cataloging all the files created by the model.
It is also used by "Recompile UI?" To search for .rsc files that
might be contained in library-style subfolders.

Inputs:
dir
  String
  The directory to search

ext
  Optional string or array of strings
  extensions to limit the search to.
  e.g. "rsc" or {"rsc", "lst", "bin"}
  If null, finds files of all types.

Output:
An array of complete paths for each file found
*/

Macro "Catalog Files" (dir, ext)

  if TypeOf(ext) = "string" then ext = {ext}

  a_dirInfo = GetDirectoryInfo(dir + "/*", "Directory")

  // If there are folders in the current directory,
  // call the macro again for each one.
  if a_dirInfo <> null then do
    for d = 1 to a_dirInfo.length do
      path = dir + "/" + a_dirInfo[d][1]

      a_files = a_files + RunMacro("Catalog Files", path, ext)
    end
  end

  // If the ext parameter is used
  if ext <> null then do
    for e = 1 to ext.length do
      path = dir + "/*." + ext[e]

      a_info = GetDirectoryInfo(path, "File")
      if a_info <> null then do
        for i = 1 to a_info.length do
          a_files = a_files + {dir + "/" + a_info[i][1]}
        end
      end
    end
  // If the ext parameter is not used
  end else do
    a_info = GetDirectoryInfo(dir + "/*", "File")
    if a_info <> null then do
      for i = 1 to a_info.length do
        a_files = a_files + {dir + "/" + a_info[i][1]}
      end
    end
  end

  return(a_files)
EndMacro

/*
Simple wrapper to "Catalog Files" that writes out the full path to
every file in given directory (and it's subdirectories) to a csv.
This is usually run manually in the GISDK toolbar. Write a temporary
macro that sets the value of "dir" and calls this macro like so:

Macro "test"
  dir  = "C:\\folder1\\folder2"
  RunMacro("List Files in CSV", dir)
  ShowMessage("Done")
End

Return
  Writes a CSV file listing all files in "dir"
*/

Macro "List Files in CSV" (dir)

  dir = RunMacro("Normalize Path", dir)

  a_files = RunMacro("Catalog Files", dir)
  file = dir + "/list_of_files.csv"
  file = OpenFile(file, "w")
  for f = 1 to a_files.length do
    WriteLine(file, a_files[f])
  end
  CloseFile(file)
EndMacro

/*
Uses the batch shell to copy the folders and subfolders from
one directory to another.

from
  String
  Full path of directory to copy

to
  String
  Full path of destination

copy_files
  "True" or "False"
  Whether or not to copy files
  Defaults to false

subdirectories
  "True" or "False"
  Whether or not to include subdirectories
  Defaults to "True"
*/

Macro "Copy Directory" (from, to, copy_files, subdirectories)

  if copy_files = null then copy_files = "False"
  if subdirectories = null then subdirectories = "True"

  // if from or to end with a "\" remove it
  if Right(from, 1) = "\\" then do
    length = StringLength(from)
    from = Substring(from, 1, length - 1)
  end
  if Right(to, 1) = "\\" then do
    length = StringLength(to)
    to = Substring(to, 1, length - 1)
  end

  from = "\"" +  from + "\""
  to = "\"" +  to + "\""
  cmd = "cmd /C xcopy " + from + " " + to + " /i /y"
  if subdirectories then cmd = cmd + " /e"
  if !copy_files then cmd = cmd + " /t"
  opts.Minimize = "True"
  RunProgram(cmd, opts)
EndMacro

/*
Uses batch shell to delete everything in a given directory.
Removes entire directory and then recreates it.
*/

Macro "Clear Directory" (dir)

  dir = "\"" +  dir + "\""
  cmd = "cmd /C rmdir /s /q " + dir
  opts.Minimize = "True"
  RunProgram(cmd, opts)

  cmd = "cmd /C mkdir " + dir
  opts.Minimize = "True"
  RunProgram(cmd, opts)
EndMacro

/*
Replacement macro for TransCADs "JoinTableToLayer()", which does not work
properly.  We have notified Caliper, who will correct it's functionality in a
future release of TransCAD.  For now, use this.

Inputs:
masterFile
  String
  Full path of master geographic or binary file

mID
  String
  Name of master field to use for join.

slaveFile
  String
  Full path of slave table.  Can be FFB or CSV.

sID
  String
  Name of slave field to use for join.

overwrite
  Boolean
  Whether or not to replace any existing
  fields with joined values.  Defaults to true.
  If false, the fields will be added with ":1".

Output:
Permanently appends the slave data to the master table

Example application:
Attaching an SE data table to a TAZ layer
*/

Macro "Perma Join" (masterFile, mID, slaveFile, sID, overwrite)

  if overwrite = null then overwrite = "True"

  // Determine master file type
  path = SplitPath(masterFile)
  if path[4] = ".dbd" then type = "dbd"
  else if path[4] = ".bin" then type = "bin"
  else Throw("Master file must be .dbd or .bin")

  // Open the master file
  if type = "dbd" then do
    {nlyr, master} = GetDBLayers(masterFile)
    master = AddLayerToWorkspace(master, masterFile, master)
    nlyr = AddLayerToWorkspace(nlyr, masterFile, nlyr)
  end else do
    masterDCB = Substitute(masterFile, ".bin", ".DCB", )
    master = OpenTable("master", "FFB", {masterFile, })
  end

  // Determine slave table type and open
  path = SplitPath(slaveFile)
  if path[4] = ".csv" then s_type = "CSV"
  else if path[4] = ".bin" then s_type = "FFB"
  else Throw("Slave file must be .bin or .csv")
  slave = OpenTable("slave", s_type, {slaveFile, })

  // If mID is the same as sID, rename sID
  if mID = sID then do
    // Can only modify FFB tables.  If CSV, must convert.
    if s_type = "CSV" then do
      tempBIN = GetTempFileName("*.bin")
      ExportView(slave + "|", "FFB", tempBIN, , )
      CloseView(slave)
      slave = OpenTable("slave", "FFB", {tempBIN, })
    end

    str = GetTableStructure(slave)
    for s = 1 to str.length do
      str[s] = str[s] + {str[s][1]}

      str[s][1] = if str[s][1] = sID then "slave" + sID
        else str[s][1]
    end
    ModifyTable(slave, str)
    sID = "slave" + sID
  end

  // Remove existing fields from master if overwriting
  if overwrite then do
    {a_mFields, } = GetFields(master, "All")
    {a_sFields, } = GetFields(slave, "All")

    for f = 1 to a_sFields.length do
      field = a_sFields[f]
      if field <> sID & ArrayPosition(a_mFields, {field}, ) <> 0
        then RunMacro("Drop Field", master, field)
    end
  end

  // Join master and slave. Export to a temporary binary file.
  jv = JoinViews("perma jv", master + "." + mID, slave + "." + sID, )
  SetView(jv)
  a_path = SplitPath(masterFile)
  tempBIN = a_path[1] + a_path[2] + "temp.bin"
  tempDCB = a_path[1] + a_path[2] + "temp.DCB"
  ExportView(jv + "|", "FFB", tempBIN, , )
  CloseView(jv)
  CloseView(master)
  CloseView(slave)

  // Swap files.  Master DBD files require a different approach
  // from bin files, as the links between the various database
  // files are more complicated.
  if type = "dbd" then do
    // Join the tempBIN to the DBD. Remove Length/Dir fields which
    // get duplicated by the DBD.
    opts = null
    opts.Ordinal = "True"
    JoinTableToLayer(masterFile, master, "FFB", tempBIN, tempDCB, mID, opts)
    master = AddLayerToWorkspace(master, masterFile, master)
    nlyr = AddLayerToWorkspace(nlyr, masterFile, nlyr)
    RunMacro("Drop Field", master, "Length:1")
    RunMacro("Drop Field", master, "Dir:1")

    // Re-export the table to clean up the bin file
    new_dbd = a_path[1] + a_path[2] + a_path[3] + "_temp" + a_path[4]
    {l_names, l_specs} = GetFields(master, "All")
    {n_names, n_specs} = GetFields(nlyr, "All")
    opts = null
    opts.[Field Spec] = l_specs
    opts.[Node Name] = nlyr
    opts.[Node Field Spec] = n_specs
    ExportGeography(master + "|", new_dbd, opts)
    DropLayerFromWorkspace(master)
    DropLayerFromWorkspace(nlyr)
    DeleteDatabase(masterFile)
    CopyDatabase(new_dbd, masterFile)
    DeleteDatabase(new_dbd)

    // Remove the sID field
    master = AddLayerToWorkspace(master, masterFile, master)
    RunMacro("Drop Field", master, sID)
    DropLayerFromWorkspace(master)

    // Delete the temp binary files
    DeleteFile(tempBIN)
    DeleteFile(tempDCB)
  end else do
    // Remove the master bin files and rename the temp bin files
    DeleteFile(masterFile)
    DeleteFile(masterDCB)
    RenameFile(tempBIN, masterFile)
    RenameFile(tempDCB, masterDCB)

    // Remove the sID field
    view = OpenTable("view", "FFB", {masterFile})
    RunMacro("Drop Field", view, sID)
    CloseView(view)
  end

EndMacro

/*
General macro to run R scripts from GISDK.  Creates a batch to run the script.
If the script fails, it adds a pause to the batch and re-runs so the error is
visible.

Input
rscriptexe  String  Path to "Rscript.exe"
rscript     String  Path to the actual r script "*.R"
OtherArgs   Array   Array of other arguments to pass to the R environment.
                    These arguments will be specific to the R script run.
                    Can be null.
*/

Macro "Run R Script" (rscriptexe, rscript, OtherArgs)

  // Create the command line call
  // Put each argument in quotes to handle potential spaces
  command = "\"" + rscriptexe + "\" \"" + rscript + "\""
  for i = 1 to OtherArgs.length do
    command = command + " \"" + OtherArgs[i] + "\""
  end

  // Create a batch file to run the R script
  batFile = GetTempFileName(".bat")
  bat = OpenFile(batFile,"w")
  WriteLine(bat,command)
  CloseFile(bat)

  // Run the batch file
  opts = null
  opts.Minimize = "True"
  ret = RunProgram(batFile, opts)

  // If the batch script fails, re-run it with a pause
  if ret <> 0 then do

    bat = OpenFile(batFile,"a")
    WriteLine(bat, "pause")
    CloseFile(bat)
    RunProgram(batFile, )

    a_path = SplitPath(rscript)
    file = a_path[3] + a_path[4]

    Throw(
      file + " did not run sucessfully.\n" +
      "It was re-run with a pause included to view the error."
      )
  end
EndMacro

/*
Adds a field.  Replacement for hidden "TCB Add View Fields", which has
some odd behavior.  Takes the same field info array.  See ModifyTable()
for the 12 potential elements.

view
  String
  view name

a_fields
  Array of arrays
  Each sub-array contains the 12-elements that describe a field.
  e.g. {"Density", "Real", 10, 3,,,,"Used to calculate initial AT"}
  (See ModifyTable() TC help page for full array info)

a_initial_values
  Array (optional)
  If provided, the field will be set to this value. This can be used to ensure
  that a field starts at null. If left blank, and the field is already present,
  then the previous values remain.
*/

Macro "Add Fields" (view, a_fields, a_initial_values)

  // Argument check
  if view = null then Throw("'view' not provided")
  if a_fields = null then Throw("'a_fields' not provided")
  if a_initial_values <> null then do
    if TypeOf(a_initial_values) <> "array"
      then Throw("'a_initial_values' must be an array")
  end

  // Get current structure and preserve current fields by adding
  // current name to 12th array position
  a_str = GetTableStructure(view)
  for s = 1 to a_str.length do
    a_str[s] = a_str[s] + {a_str[s][1]}
  end
  for f = 1 to a_fields.length do
    a_field = a_fields[f]

    // Test if field already exists (will do nothing if so)
    field_name = a_field[1]
    exists = "False"
    for s = 1 to a_str.length do
      if a_str[s][1] = field_name then exists = "True"
    end

    // If field does not exist, create it
    if !exists then do
      dim a_temp[12]
      for i = 1 to a_field.length do
        a_temp[i] = a_field[i]
      end
      a_str = a_str + {a_temp}
    end
  end

  ModifyTable(view, a_str)

  // Set initial field values if provided
  if a_initial_values <> null then do
    length = GetRecordCount(view, )
    for f = 1 to a_initial_values.length do
      field = a_fields[f][1]
      type = a_fields[f][2]
      init_value = a_initial_values[f]

      if type = "Character" then type = "String"

      opts = null
      opts.Constant = init_value
      v = Vector(length, type)
      SetDataVector(view + "|", field, v, )
    end
  end
EndMacro

/*
table   String Can be a file path or view of the table to modify
field   Array or string
string  Array or string
*/

Macro "Add Field Description" (table, field, description)

  if table = null or field = null or description = null then Throw(
    "Missing arguments to 'Add Field Description'"
    )
  if TypeOf(field) = "string" then field = {field}
  if TypeOf(description) = "string" then description = {description}
  if field.length <> description.length then Throw(
    "The same number of fields and descriptions must be provided."
  )
  isView = RunMacro("Is View?", table)

  // If the table variable is not a view, then attempt to open it
  if isView = "no" then table = OpenTable("table", "FFB", {table})

  str = GetTableStructure(table)
  for f = 1 to str.length do
    str[f] = str[f] + {str[f][1]}
    name = str[f][1]

    pos = ArrayPosition(field, {name}, )
    if pos <> 0 then str[f][8] = description[pos]
  end
  ModifyTable(table, str)

  // If this macro opened the table, close it
  if isView = "no" then CloseView(table)
EndMacro

/*
Renames a field in a TC view

Inputs
  view_name
    String
    Name of view to modify

  current_name
    String
    Name of field to rename

  new_name
    String
    New name to use
*/

Macro "Rename Field" (view_name, current_name, new_name)

  // Argument Check
  if view_name = null then Throw("Rename Field: 'view_name' not provided")
  if current_name = null then Throw("Rename Field: 'current_name' not provided")
  if new_name = null then Throw("Rename Field: 'new_name' not provided")

  // Get and modify the field info array
  a_str = GetTableStructure(view_name)
  field_modified = "false"
  for s = 1 to a_str.length do
    a_field = a_str[s]
    field_name = a_field[1]

    // Add original field name to end of field array
    a_field = a_field + {field_name}

    // rename field if it's the current field
    if field_name = current_name then do
      a_field[1] = new_name
      field_modified = "true"
    end

    a_str[s] = a_field
  end

  // Modify the table
  ModifyTable(view_name, a_str)

  // Throw error if no field was modified
  if !field_modified
    then Throw(
      "Rename Field: Field '" + current_name +
      "' not found in view '" + view_name + "'"
    )
EndMacro

/*
Tests whether or not a string is a view name or not
*/

Macro "Is View?" (string)

  a_views = GetViewNames()
  if ArrayPosition(a_views, {string}, ) = 0 then return("no")
  else return("yes")
EndMacro


/*
Many steps in the model boil down to simply aggregating/disaggregating
fields - applying a factor during the process.

MacroOpts
  Options array
  Contains all required arguments

  MacroOpts.tbl
    String
    Path to table file where the cross walk will take place.

  MacroOpts.equiv_tbl
    The CSV file used to convert.  Must have a "from_field", "to_field", "to_desc",
    and "from_factor" columns.  Data in the from_field is added into to_field
    after applying the factor.  "to_desc" is used as the field description for the
    "to_field" and helps users understand model output.

  MacroOpts.field_prefix
  MacroOpts.field_suffix
    Optional String
    Prefix/Suffix applied to "from_field" and "to_field" when getting/setting
    values. Commonly used to prevent the equiv_tbl from repeating itself over
    things like time of day.  For example, if HBS is being collapsed into HBO,
    and you don't want the equiv table to look like this:

    from_field  to_field  ...
    HBS_AM      HBO_AM
    HBS_MD      HBO_MD
    ...

    Simply have the equiv table look like this:

    to_field  from_field  ...
    HBO       HBS

    And loop over time of day passing the suffix into the function for each
    period. e.g.

    opts.tbl = tbl
    opts.equiv_tbl = equiv_tbl
    opts.suffix = "_AM"
    RunMacro("Field Crosswalk", opts)
    opts.suffix = "_MD"
    RunMacro("Field Crosswalk", opts)
    ...

    The macro will look for "HBS_AM" in the table and convert to "HBO_AM".
*/

Macro "Field Crosswalk" (MacroOpts)

  // Argument extraction
  tbl = MacroOpts.tbl
  equiv_tbl = MacroOpts.equiv_tbl
  field_prefix = MacroOpts.field_prefix
  field_suffix = MacroOpts.field_suffix

  // Open tables
  equiv_tbl = OpenTable("param", "CSV", {equiv_tbl})
  tbl = OpenTable("se", "FFB", {tbl})

  // Only work with equiv_tbl rows that aren't null
  SetView(equiv_tbl)
  qry = "Select * where from_field <> null"
  n = SelectByQuery("not_null", "several", qry)
  if n = 0 then Throw("Field Crosswalk: equiv_tbl is empty")

  // Get from-field, to-field, factor, and description vectors
  v_to_field = GetDataVector(equiv_tbl + "|not_null", "to_field", )
  v_to_desc = GetDataVector(equiv_tbl + "|not_null", "to_desc", )
  v_from_field = GetDataVector(equiv_tbl + "|not_null", "from_field", )
  v_from_fac = GetDataVector(equiv_tbl + "|not_null", "from_factor", )

  // Zero out any existing "to" fields to prevent build up
  opts = null
  opts.Unique = "True"
  v_uniq_to = SortVector(v_to_field)
  a_fnames = GetFields(tbl, "All")
  a_fnames = a_fnames[1]
  for t = 1 to v_uniq_to.length do
    to_field = field_prefix + v_uniq_to[t] + field_suffix

    if ArrayPosition(a_fnames, {to_field}, ) <> 0 then do
      v_to = nz(GetDataVector(tbl + "|", to_field, ))
      v_to = if (abs(nz(v_to)) >= 0) then 0 else v_to
      SetDataVector(tbl + "|", to_field, v_to, )
    end
  end

  // Loop over each "from" field listed in the parameter table
  // and add their values (multiplied by their factors) to the "to" fields
  for f = 1 to v_from_field.length do
    from_field = v_from_field[f]
    to_field = v_to_field[f]
    desc = v_to_desc[f]
    factor = v_from_fac[f]

    // Add prefix/suffix
    from_field = field_prefix + from_field + field_suffix
    to_field = field_prefix + to_field + field_suffix

    a_fields = {{
      to_field, "Real", 10, 2,,,,
      desc
    }}
    RunMacro("TCB Add View Fields", {tbl, a_fields})

    v_from = nz(GetDataVector(tbl + "|", from_field, ))
    v_to = nz(GetDataVector(tbl + "|", to_field, ))
    v_to = v_to + v_from * factor
    SetDataVector(tbl + "|", to_field, v_to, )
  end

  CloseView(equiv_tbl)
  CloseView(tbl)
EndMacro

/*
Similar to the crosswalk macro for fields, but for matrix cores.
The destination matrix is always recreated from scratch.
Each core is then added.

MacroOpts
  Named array of function arguments

  from_mtx
    String
    Full path to matrix file to take cores from

  to_mtx
    String
    Full path to matrix file where cores will be added
    Always creates a new matrix (deletes to_mtx if it exists).

  to_mtx_label
    Optional String
    Name/Label to assign to to_mtx. By default, uses
    "Created by Matrix Crosswalk"

  equiv_tbl
    String
    Full path to parameter CSV files that describes crosswalk
*/

Macro "Matrix Crosswalk" (MacroOpts)

  from_mtx = MacroOpts.from_mtx
  to_mtx = MacroOpts.to_mtx
  equiv_tbl = MacroOpts.equiv_tbl
  to_mtx_label = MacroOpts.to_mtx_label

  if from_mtx = null then Throw("'from_mtx' not provided")
  if to_mtx = null then Throw("'to_mtx' not provided")
  if equiv_tbl = null then Throw("'equiv_tbl' not provided")
  if to_mtx_label = null then to_mtx_label = "Created by Matrix Crosswalk"

  // Open the equiv_tbl
  // Get from-core, to-core, and factor
  vw_eq = OpenTable("param", "CSV", {equiv_tbl})
  v_to_core = GetDataVector(vw_eq + "|", "to_core", )
  v_from_core = GetDataVector(vw_eq + "|", "from_core", )
  v_from_fac = GetDataVector(vw_eq + "|", "from_factor", )
  CloseView(vw_eq)
  DeleteFile(Substitute(equiv_tbl, ".csv", ".DCC", ))

  // Open from_mtx and create currencies
  from_mtx = OpenMatrix(from_mtx, )
  {from_ri, from_ci} = GetMatrixIndex(from_mtx)
  a_from_curs = CreateMatrixCurrencies(from_mtx, from_ri, from_ci, )

  // Create matrix
  if GetFileInfo(to_mtx) <> null then DeleteFile(to_mtx)
  opts = null
  opts.[File Name] = to_mtx
  opts.Label = to_mtx_label
  opts.Tables = {v_to_core[1]}
  to_mtx = CopyMatrixStructure({a_from_curs.(v_from_core[1])}, opts)
  {to_ri, to_ci} = GetMatrixIndex(to_mtx)

  // Loop over every row of the equiv_tbl
  for c = 1 to v_to_core.length do
    to_core = v_to_core[c]
    from_core = v_from_core[c]
    factor = v_from_fac[c]

    // Check that the from_core was found.
    if a_from_curs.(from_core) = null
      then Throw(
        "Matrix Crosswalk: from_core '" + from_core + "' not found in matrix"
      )

    // Create the to core if it doesn't already exist and create currency
    a_corenames = GetMatrixCoreNames(to_mtx)
    if ArrayPosition(a_corenames, {to_core}, ) = 0 then
      AddMatrixCore(to_mtx, to_core)
    to_cur = CreateMatrixCurrency(to_mtx, to_core, to_ri, to_ci, )

    // Calculate the new core
    to_cur := nz(to_cur) + nz(a_from_curs.(from_core)) * factor

  end
EndMacro

/*
This macro takes two vectors and calculates the RMSE

v_target and v_compare
  Vectors or arrays
  Vectors of data to be compared
*/

Macro "Calculate Vector RMSE" (v_target, v_compare)

  // Argument check
  if v_target.length = null then Throw("Missing 'v_target'")
  if v_compare.length = null then Throw("Missing 'v_compare'")
  if TypeOf(v_target) = "array" then v_target = A2V(v_target)
  if TypeOf(v_compare) = "array" then v_target = A2V(v_compare)
  if TypeOf(v_target) <> "vector" then Throw("'v_target' must be vector or array")
  if TypeOf(v_compare) <> "vector" then Throw("'v_compare' must be vector or array")
  if v_target.length <> v_compare.length then Throw("Vectors must be the same length")

  n = v_target.length
  tot_target = VectorStatistic(v_target, "Sum", )
  tot_result = VectorStatistic(v_compare, "Sum", )

  // RMSE and Percent RMSE
  diff_sq = Pow(v_target - v_compare, 2)
  sum_sq = VectorStatistic(diff_sq, "Sum", )
  rmse = sqrt(sum_sq / n)
  pct_rmse = 100 * rmse / (tot_target / n)
  return({rmse, pct_rmse})
EndMacro

/*
Takes a path like this:
C:\\projects\\model\\..\\other_model

and turns it into this:
C:\\projects\\other_model

Works whether using "\\" or "/" for directory markers

Also removes any trailing slashes
*/

Macro "Normalize Path" (rel_path)

  a_parts = ParseString(rel_path, "/\\")
  for i = 1 to a_parts.length do
    part = a_parts[i]

    if part <> ".." then do
      a_path = a_path + {part}
    end else do
      a_path = ExcludeArrayElements(a_path, a_path.length, 1)
    end
  end

  for i = 1 to a_path.length do
    if i = 1
      then path = a_path[i]
      else path = path + "\\" + a_path[i]
  end

  return(path)
EndMacro

Macro "Resolve Path" (rel_path)
  Throw("Macro 'Resolve Path' has been renamed to 'Normalize Path'")
EndMacro

/*
Takes a query string and makes sure it is of the form:
"Select * where ...""

Inputs
  query
    String
    A query. Can be "Select * where ID = 1" or just the "ID = 1"

Returns
  A query of the form "Select * where ..."
*/

Macro "Normalize Query" (query)

  if query = null then Throw("Normalize Query: 'query' not provided")

  if Left(query, 15) = "Select * where "
    then return(query)
    else return("Select * where " + query)
EndMacro

/*
Creates a simple .net file using just the length attribute. Many processes
require a network

Inputs
  MacroOpts
    Named array holding all arguments. (e.g. MacroOpts.hwy_dbd)

    llyr
      Optional String
      Name of line layer to create network from. If provided, the macro assumes
      the layer is already in the workspace. Either 'llyr' or 'hwy_dbd' must
      be provided.

    hwy_dbd
      Optional String
      Full path to the highway DBD file to create a network. If provided, the
      macro assumes that it is not already open in the workspace.Either 'llyr'
      or 'hwy_dbd' must be provided.

    centroid_qry
      Optional String
      Query defining centroid set. If null, a centroid set will not be created.

Returns
  net_file
    String
    Full path to the network file
*/

Macro "Create Simple Highway Net" (MacroOpts)

  RunMacro("TCB Init")

  // Argument extraction
  llyr = MacroOpts.llyr
  llyr_provided = if (llyr <> null) then "true" else "false"
  hwy_dbd = MacroOpts.hwy_dbd
  hwy_dbd_provided = if (hwy_dbd <> null) then "true" else "false"
  centroid_qry = MacroOpts.centroid_qry

  // Argument checking
  if !llyr_provided and !hwy_dbd_provided = null then Throw(
    "Either 'llyr' or 'hwy_dbd' must be provided."
  )
  if llyr_provided and hwy_dbd_provided then Throw(
    "Provide only 'llyr' or 'hwy_dbd'. Not both."
  )

  // If llyr is provided, get the hwy_dbd
  // Get info about hwy_dbd
  if llyr_provided then do
    map = GetMap()
    SetLayer(llyr)
    if map = null then Throw("Simple Network: 'llyr' must be in current map")
    a_layers = GetMapLayers(map, "Line")
    in_map = if (ArrayPosition(a_layers, {llyr}, ) = 0) then "false" else "true"
    if !in_map then Throw("Simple Network: 'llyr' must be in the current map")

    hwy_dbd = GetLayerDB(llyr)
    {nlyr, } = GetDBLayers(hwy_dbd)
  // if hwy_dbd is provided, open it in a map
  end else do
    {nlyr, llyr} = GetDBLayers(hwy_dbd)
    map = RunMacro("G30 new map", hwy_dbd)
  end
  a_path = SplitPath(hwy_dbd)
  out_dir = RunMacro("Normalize Path", a_path[1] + a_path[2])

  // Create a simple network of the scenario highway layer
  SetLayer(llyr)
  set_name = null
  net_file = out_dir + "/simple.net"
  label = "Simple Network"
  link_fields = {{"Length", {llyr + ".Length", llyr + ".Length", , , "False"}}}
  node_fields = null
  opts = null
  opts.[Time Units] = "Minutes"
  opts.[Length Units] = "Miles"
  opts.[Link ID] = llyr + ".ID"
  opts.[Node ID] = nlyr + ".ID"
  opts.[Turn Penalties] = "Yes"
  nh = CreateNetwork(set_name, net_file, label, link_fields, node_fields, opts)

  // Add centroids to the network to prevent routes from passing through
  // Network Settings
  if centroid_qry <> null then do

    centroid_qry = RunMacro("Normalize Query", centroid_qry)

    Opts = null
    Opts.Input.Database = hwy_dbd
    Opts.Input.Network = net_file
    Opts.Input.[Centroids Set] = {
      hwy_dbd + "|" + nlyr, nlyr,
      "centroids", centroid_qry
    }
    ok = RunMacro("TCB Run Operation", "Highway Network Setting", Opts, &Ret)
    if !ok then Throw(
      "Simple Network: Setting centroids failed"
    )
  end

  // Workspace clean up.
  // If this macro create the map, then close it.
  if hwy_dbd_provided then CloseMap(map)

  return(net_file)
EndMacro

/*
Macro to simplify the process of map creation.

Inputs
  MacroOpts
    Named array that holds argument names

    file
      String
      Full path to the file to map. Supported types:
        Point, Line, Polygon geographic files. RTS files.

    minimized
      Optional String ("true" or "false")
      Defaults to "true".
      Whether to minimize the map. Makes a number of geospatial calculations
      faster if the map does not have to be redrawn.

Returns
  An array of two things:
  1. the name of the map
  2. an array of layer names
*/

Macro "Create Map" (MacroOpts)

  // Argument extraction
  file = MacroOpts.file
  minimized = MacroOpts.minimized

  // Argument checking
  if file = null then Throw("Create Map: 'file' not provided")
  if minimized = null then minimized = "true"

  // Determine file extension
  {drive, directory, filename, ext} = SplitPath(file)
  if Lower(ext) = ".dbd" then file_type = "dbd"
  else if Lower(ext) = ".rts" then file_type = "rts"
  else Throw("Create Map: 'file' must be either a '.dbd.' or '.rts' file")

  // Get a unique name for the map
  map_name = RunMacro("Get Unique Map Name")

  // Create the map if a dbd file was passed
  if file_type = "dbd" then do
    a_layers = GetDBLayers(file)
    {scope, label, rev} = GetDBInfo(file)
    opts = null
    opts.scope = scope
    map_name = CreateMap(map_name, opts)
    if minimized then MinimizeWindow(GetWindowName())
    for layer in a_layers do
      AddLayer(map_name, layer, file, layer)
      RunMacro("G30 new layer default settings", layer)
    end
  end

  // Create the map if a RTS file was passed
  if file_type = "rts" then do

    // Get the RTS's highway file
    opts = null
    opts.rts_file = file
    hwy_dbd = RunMacro("Get RTS Highway File", opts)
    {scope, label, rev} = GetDBInfo(hwy_dbd)
    opts = null
    opts.Scope = scope
    map = CreateMap(map_name, opts)
    if minimized then MinimizeWindow(GetWindowName())
    {, , opts} = GetRouteSystemInfo(file)
    rlyr = opts.Name
    a_layers = AddRouteSystemLayer(map, rlyr, file, )
    for layer in a_layers do
      RunMacro("G30 new layer default settings", layer)
    end
  end

  return({map_name, a_layers})
EndMacro

/*
Helper to "Create Map" macro.
Avoids duplciating map names by using an odd name and checking to make
sure that map name does not already exist.

Similar to "unique_view_name" in gplyr.
*/

Macro "Get Unique Map Name"
  {map_names, idx, cur_name} = GetMaps()
  if map_names.length = 0 then do
    map_name = "gisdk_tools1"
  end else do
    num = 0
    exists = "True"
    while exists do
      num = num + 1
      map_name = "gisdk_tools" + String(num)
      exists = if (ArrayPosition(map_names, {map_name}, ) <> 0)
        then "True"
        else "False"
    end
  end

  return(map_name)
EndMacro

/*
Makes a copy of all the files comprising a route system.
Optionally includes the highway dbd.

Inputs

  MacroOpts
    Named array containing all argument macros

    from_rts
      String
      Full path to the route system to copy. Ends in ".rts"

    to_dir
      String
      Full path to the directory where files will be copied

    include_hwy_files
      Optional True/False
      Whether to also copy the highway files. Defaults to false. Because of the
      fragile nature of the RTS file, the highway layer is first assumed to be
      in the same folder as the RTS file. If it isn't, GetRouteSystemInfo() will
      be used to try and locate it; however, this method is prone to errors if
      the route system is in different places on different machines. As a general
      rule, always keep the highway layer and the RTS layer together.

Returns
  rts_file
    String
    Full path to the resulting .RTS file
*/

Macro "Copy RTS Files" (MacroOpts)

  // Argument extraction
  from_rts = MacroOpts.from_rts
  to_dir = MacroOpts.to_dir
  include_hwy_files = MacroOpts.include_hwy_files

  // Argument check
  if from_rts = null then Throw("Copy RTS Files: 'from_rts' not provided")
  if to_dir = null then Throw("Copy RTS Files: 'to_dir' not provided")
  to_dir = RunMacro("Normalize Path", to_dir)

  // Get the directory containing from_rts
  a_rts_path = SplitPath(from_rts)
  from_dir = RunMacro("Normalize Path", a_rts_path[1] + a_rts_path[2])
  to_rts = to_dir + "/" + a_rts_path[3] + a_rts_path[4]

  // Create to_dir if it doesn't exist
  if GetDirectoryInfo(to_dir, "All") = null then CreateDirectory(to_dir)

  // Get all files comprising the route system
  {a_names, a_sizes} = GetRouteSystemFiles(from_rts)
  for file_name in a_names do
    from_file = from_dir + "/" + file_name
    to_file = to_dir + "/" + file_name
    CopyFile(from_file, to_file)
  end

  // If also copying the highway files
  if include_hwy_files then do

    // Get the highway file. Use gisdk_tools macro to avoid common errors
    // with GetRouteSystemInfo()
    opts = null
    opts.rts_file = from_rts
    from_hwy_dbd = RunMacro("Get RTS Highway File", opts)

    // Use the to_dir to create the path to copy to
    a_path = SplitPath(from_hwy_dbd)
    to_hwy_dbd = to_dir + "/" + a_path[3] + a_path[4]

    CopyDatabase(from_hwy_dbd, to_hwy_dbd)

    // Return both resulting RTS and DBD
    return({to_rts, to_hwy_dbd})
  end

  // Return the resulting RTS file
  return(to_rts)
EndMacro

/*
Because of the fragile nature of the RTS file, GetRouteSystemInfo() can often
return highway file paths that are incorrect. This macro checks to see if the
highway file returned by GetRouteSystemInfo() exists. If not, it looks in the
directory of the route system file.

Inputs
  MacroOpts
    Named array that holds macro arguments

    rts_file
      String
      Full path to the RTS file whose highway file you want to locate.

Returns
  String - full path to the highway file associated with the RTS.
*/

Macro "Get RTS Highway File" (MacroOpts)

  // Argument extraction
  rts_file = MacroOpts.rts_file

  // Argument checking
  if rts_file = null then Throw("Get RTS Highway File: 'rts_file' not provided")

  // Start by assuming the route system info is correct
  a_rts_info = GetRouteSystemInfo(rts_file)
  hwy_dbd = a_rts_info[1]

  // If the highway file does not exist at the path according to the rts file,
  // assume it is in the same directory as the RTS.
  // Use the RTS file to get the name of the highway file.
  if GetFileInfo(hwy_dbd) = null then do
    a_path = SplitPath(hwy_dbd)
    a_rts_path = SplitPath(rts_file)
    hwy_dbd = a_rts_path[1] + a_rts_path[2] + a_path[3] + a_path[4]
  end

  // If there is no file at that path, throw an error message
  if GetFileInfo(hwy_dbd) = null
    then Throw(
      "Get RTS Highway File: The highway network associated with this RTS\n" +
      "cannot be found in the same directory as the RTS nor at: \n" +
      hwy_dbd
    )

  return(hwy_dbd)
EndMacro

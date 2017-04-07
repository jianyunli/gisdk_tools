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
*/

Macro "Add Fields" (view, a_fields)

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

    from_field  to_field  ...
    HBS      HBO

    And loop over time of day passing the suffix into the function for each
    period. e.g.

    RunMacro("Field Crosswalk", tbl, equiv_tbl, "_AM")
    RunMacro("Field Crosswalk", tbl, equiv_tbl, "_MD")
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

  // Get from-field, to-field, factor, and description vectors
  v_to_field = GetDataVector(equiv_tbl + "|", "to_field", )
  v_to_desc = GetDataVector(equiv_tbl + "|", "to_desc", )
  v_from_field = GetDataVector(equiv_tbl + "|", "from_field", )
  v_from_fac = GetDataVector(equiv_tbl + "|", "from_factor", )

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
    If it does not exist, it will be created.

  equiv_tbl
    String
    Full path to parameter CSV files that describes crosswalk
*/

Macro "Matrix Crosswalk" (MacroOpts)

  from_mtx = MacroOpts.from_mtx
  to_mtx = MacroOpts.to_mtx
  equiv_tbl = MacroOpts.equiv_tbl

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
  opts.Label = "Created by Matrix Crosswalk"
  opts.Tables = {v_to_core[1]}
  to_mtx = CopyMatrixStructure({a_from_curs.(v_from_core[1])}, opts)
  {to_ri, to_ci} = GetMatrixIndex(to_mtx)

  // Loop over every row of the equiv_tbl
  for c = 1 to v_to_core.length do
    to_core = v_to_core[c]
    from_core = v_from_core[c]
    factor = v_from_fac[c]

    // Create the to core if it doesn't already exist and create currency
    a_corenames = GetMatrixCoreNames(to_mtx)
    if ArrayPosition(a_corenames, {to_core}, ) = 0 then
      AddMatrixCore(to_mtx, to_core)
    to_cur = CreateMatrixCurrency(to_mtx, to_core, to_ri, to_ci, )

    // Calculate the new core
    to_cur := nz(to_cur) + a_from_curs.(from_core) * factor

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
*/

Macro "Resolve Path" (rel_path)

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

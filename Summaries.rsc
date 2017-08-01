/*
Collection of scripts that create maps or tables to summarize model output
*/

/*
For base model calibration, maps comparing model and count volumes are required.
This macro creates a standard map to show absolute and percent differences in a
color theme. It also performs maximum desirable deviation calculations and
highlights (in green) links that do not exceed the MDD.

Inputs
  macro_opts
    Named array of macro arguments

    output_file
      String
      Complete path of the output map to create.

    hwy_dbd
      String
      Complete path to the highway geographic file.

    count_id_field
      String
      Field name of the count ID. The count ID field is used to determine
      where a single count has been split between multiple links (like on a
      freeway).

    count_field
      String
      Name of the field containing the count volume. Can be a daily or period
      count field, but time period between count and volume fields should
      match.

    vol_field
      String
      Name of the field containing the model volume. Can be a daily or period
      count field, but time period between count and volume fields should
      match.

    field_suffix
      Optional string
      "" by default. If provided, will be appended to the fields created by this
      macro. For example, if making a count difference map of SUT vs SUT counts,
      you could provide a suffix of "SUT". This would lead to fields created
      like "Count_SUT", "Volume_SUT", "diff_SUT", etc. This is used to prevent
      repeated calls to this macro from overwriting these fields.

Depends
  gplyr
*/

Macro "Count Difference Map" (macro_opts)

  output_file = macro_opts.output_file
  hwy_dbd = macro_opts.hwy_dbd
  count_id_field = macro_opts.count_id_field
  count_field = macro_opts.count_field
  vol_field = macro_opts.vol_field
  field_suffix = macro_opts.field_suffix

  // set the field suffix
  if field_suffix = null then field_suffix = ""
  if field_suffix <> "" then do
    if field_suffix[1] <> "_" then field_suffix = "_" + field_suffix
  end

  // Determine output directory (removing trailing backslash)
  a_path = SplitPath(output_file)
  output_dir = a_path[1] + a_path[2]
  len = StringLength(output_dir)
  output_dir = Left(output_dir, len - 1)

  // Create output directory if it doesn't exist
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  // Create map
  map = RunMacro("G30 new map", hwy_dbd)
  {nlyr, vw} = GetDBLayers(hwy_dbd)
  SetLayer(vw)
  MinimizeWindow(GetWindowName())

  // Add fields for mapping
  a_fields = {
    {"NumCountLinks","Integer",8,,,,, "Number of links with this count ID"},
    {"Count","Integer",8,,,,, "Repeat of the count field"},
    {"Volume","Real",8,,,,, "Total Daily Link Flow"},
    {"diff","Integer",8,,,,, "Volume - Count"},
    {"absdiff","Integer",8,,,,, "abs(diff)"},
    {"pctdiff","Integer",8,,,,, "diff / Count * 100"},
    {"MDD","Integer",8,,,,, "Maximum Desirable Deviation"},
    {"ExceedMDD","Integer",8,,,,, "If link exceeds MDD"}
  }
  RunMacro("TCB Add View Fields", {vw, a_fields})

  // Create data frame
  df = CreateObject("df")
  opts = null
  opts.view = vw
  opts.fields = {count_id_field, count_field, vol_field}
  df.read_view(opts)
  df.rename(count_field, "Count")
  df.rename(vol_field, "Volume")

  // Aggregate by count ID
  df2 = df.copy()
  df2.group_by(count_id_field)
  opts = null
  opts.Count = {"sum"}
  opts.Volume = {"sum"}
  df2.summarize(opts)
  df2.filter(count_id_field + " <> null")
  df2.rename("Count", "NumCountLinks")

  // Join aggregated data back to disaggregate column of count IDs
  df.select(count_id_field)
  df.left_join(df2, count_id_field, count_id_field)
  df.rename("sum_Count", "Count")
  df.rename("sum_Volume", "Volume")

  // Calculate remaining fields
  df.mutate("diff", df.tbl.Volume - df.tbl.Count)
  df.mutate("absdiff", abs(df.tbl.diff))
  df.mutate("pctdiff", df.tbl.diff / df.tbl.Count * 100)
  v_c = df.tbl.Count
  v_MDD = if (v_c <= 50000) then (11.65 * Pow(v_c, -.37752)) * 100
     else if (v_c <= 90000) then (400 * Pow(v_c, -.7)) * 100
     else if (v_c <> null)  then (.157 - v_c * .0000002) * 100
     else null
  df.mutate("MDD", v_MDD)
  v_exceedMDD = if abs(df.tbl.pctdiff) > v_MDD then 1 else 0
  df.mutate("ExceedMDD", v_exceedMDD)

  // Fill data view
  df.update_view(vw)

  // Rename fields to add suffix (and remove any that already exist)
  for f = 1 to a_fields.length do
    cur_field = a_fields[f][1]

    new_field = cur_field + field_suffix
    RunMacro("Remove Field", vw, new_field)
    RunMacro("Rename Field", vw, cur_field, new_field)
  end

  // Scaled Symbol Theme
  SetLayer(vw)
  flds = {vw + ".absdiff" + field_suffix}
  opts = null
  opts.Title = "Absolute Difference"
  opts.[Data Source] = "All"
  opts.[Minimum Value] = 0
  opts.[Maximum Value] = 50000
  opts.[Minimum Size] = .25
  opts.[Maximum Size] = 12
  theme_name = CreateContinuousTheme("Flows", flds, opts)

  // Set color to white to make it disappear in legend
  dual_colors = {ColorRGB(65535,65535,65535)}
  // without black outlines
  dual_linestyles = {LineStyle({{{1, -1, 0}}})}
  // with black outlines
  /*dual_linestyles = {LineStyle({{{2, -1, 0},{0,0,1},{0,0,-1}}})}*/
  dual_linesizes = {0}
  SetThemeLineStyles(theme_name , dual_linestyles)
  SetThemeLineColors(theme_name , dual_colors)
  SetThemeLineWidths(theme_name , dual_linesizes)

  ShowTheme(, theme_name)

  // Apply the color theme breaks
  cTheme = CreateTheme(
    "Count % Difference", vw+".pctdiff" + field_suffix, "Manual", 8,{
      {"Values",{
        {-100, "True", -50, "False"},
        {-50, "True", -30, "False"},
        {-30, "True", -10, "False"},
        {-10, "True", 10, "True"},
        {10, "False", 30, "True"},
        {30, "False", 50, "True"},
        {50, "False", 100, "True"},
        {100, "False", 10000, "True"}
        }},
      {"Other", "False"}
    }
  )

    // Set color theme line styles and colors
    line_colors =	{
      ColorRGB(17733,30069,46260),
      ColorRGB(29812,44461,53713),
      ColorRGB(43947,55769,59881),
      ColorRGB(0,0,0),
      ColorRGB(65278,57568,37008),
      ColorRGB(65021,44718,24929),
      ColorRGB(62708,28013,17219),
      ColorRGB(55255,12336,10023)
    }
    solidline = LineStyle({{{1, -1, 0}}})
    // This one puts black borders around the line
    /*dualline = LineStyle({{{2, -1, 0},{0,0,1},{0,0,-1}}})*/

    for i = 1 to 8 do
      class_id = GetLayer() +"|" + cTheme + "|" + String(i)
      SetLineStyle(class_id, dualline)
      SetLineColor(class_id, line_colors[i])
      SetLineWidth(class_id, 2)
    end

  // Change the labels of the classes (how the divisions appear in the legend)
  labels = {
    "-100 to -50", "-50 to -30", "-30 to -10",
    "-10 to 10", "10 to 30", "30 to 50",
    "50 to 100", ">100"
  }
  SetThemeClassLabels(cTheme, labels)

  ShowTheme(,cTheme)

  // Create a selection set of the links that do not exceed the MDD
  setname = "Deviation does not exceed MDD"
  RunMacro("G30 create set", setname)
  SelectByQuery(
    setname, "Several",
    "Select * where nz(Count" + field_suffix +
    ") > 0 and ExceedMDD" + field_suffix + " = 0"
  )
  SetLineColor(vw + "|" + setname, ColorRGB(11308, 41634, 24415))

  // Configure Legend
  RunMacro("G30 create legend", "Theme")
  SetLegendSettings (
    GetMap(),
    {
      "Automatic",
      {0, 1, 0, 1, 1, 4, 0},
      {1, 1, 1},
      {"Arial|Bold|16", "Arial|9", "Arial|Bold|16", "Arial|12"},
      {"", vol_field + " vs " + count_field}
    }
  )
  str1 = "XXXXXXXX"
  solid = FillStyle({str1, str1, str1, str1, str1, str1, str1, str1})
  SetLegendOptions (GetMap(), {{"Background Style", solid}})

  // Save map
  RedrawMap(map)
  RestoreWindow(GetWindowName())
  SaveMap(map, output_file)
  CloseMap(map)
EndMacro

/*
Simplifies the creation of chart themes

macro_opts
  Named array

  layer (required)
    String
    Layer name

  field_specs (required)
    Array of strings
    Field specs to include in chart (viewname.fieldname)

  type (required)
    "Pie", "Bar", or "Stack"

  ... (optional)
    Other arguments passed to CreateChartTheme() for customization
    See TC help for those option names. Defaults are assumed unless provided.
    e.g. include `[Minimum Size] = 5` to change the minimum size option.
*/

Macro "Create Chart Theme" (macro_opts)

  // Check that all required options are present
  layer = macro_opts.layer
  field_specs = macro_opts.field_specs
  type = macro_opts.type
  if layer = null
    then Throw("Missing 'layer' variable")
    else do
      layers = GetLayerNames()
      if ArrayPosition(layers, {layer}, ) = null
        then Throw("Layer '" + layer + "' not found'")
    end
  if field_specs = null
    then Throw("Missing 'field_specs' variable")
  if type = null
    then Throw("Missing 'type' variable")

  // Create default options
  def_opts = null
  def_opts.Title = layer + " " + type + " Theme"
  def_opts.[Data Source] = "All"
  def_opts.[Minimum Value] = null
  def_opts.[Maximum Value] = null
  def_opts.[Minimum Size] = 5
  def_opts.[Maximum Size] = 30
  def_opts.[Width] = 14
  def_opts.[3D] = "False"
  def_opts.[Direction] = "Vertical"

  // Create final options
  opts = null
  for o = 1 to def_opts.length do
    name = def_opts[o][1]

    if macro_opts.(name) <> null
      then opts.(name) = macro_opts.(name)
      else opts.(name) = def_opts.(name)
  end

  // Determine a unique theme name
  existing_names = GetThemes()
  theme_name = "Theme1" // if no existing themes
  for n = 1 to existing_names.length do
    test_name = "Theme" + String(n)
    if ArrayPosition(theme_names, {test_name}, ) = null
      then do
        theme_name = test_name
        n = existing_names.length + 1
      end
  end

  // Create Theme
  theme = CreateChartTheme(theme_name, field_specs, type, opts)

  // Set Theme Styles
  red = ColorRGB(55255, 6425, 7196)
  green = ColorRGB(19789, 44204, 9766)
  opts = null
  opts.method = "HSV"
  opts.spiral = "LONG"
  palette = GeneratePalette(red, green, field_specs.length - 2, opts)
  SetThemeFillColors(theme, palette)
  str1 = "XXXXXXXX"
  solid = FillStyle({str1, str1, str1, str1, str1, str1, str1, str1})
  SetThemeFillStyles(theme, {solid})
  solid = LineStyle({{{1, -1, 0}}})
  SetThemeLineStyles(theme, {solid})
  SetThemeLineColors(theme, {ColorRGB(10000, 10000, 10000)})

  // Show theme
  ShowTheme(, theme)
  RedrawMap(GetMap())
EndMacro

/*
Uses the outviz R package to create an assignment validation report.

Input:
MacroOpts
  Named array of arguments

  rscriptexe
    String
    Full path to the Rscript.exe file in the R directory

  rmd
    String
    Full path to the assignment validation Rmd to use

  pandoc_dir
    String
    Full path to the pandoc directory. This is required to knit the Rmd.

  output_dir
    String
    Full path to the folder where the knit output will be stored

  hwy_dbd
    String
    Full path to the loaded highway network

Depends
  R (primarily the outviz package)
*/

Macro "Outviz Assignment Validation" (MacroOpts)

  // Extract arguments
  rscriptexe = MacroOpts.rscriptexe
  rmd = MacroOpts.rmd
  pandoc_dir = MacroOpts.pandoc_dir
  output_dir = MacroOpts.output_dir
  hwy_dbd = MacroOpts.hwy_dbd

  // Copy the rmarkdown file into the output folder
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)
  outputRMD = output_dir + "/Assignment_Validation.Rmd"
  CopyFile(rmd, outputRMD)

  // Create a csv file of the link table
  {nLyr, lLyr} = GetDBLayers(hwy_dbd)
  AddLayerToWorkspace(lLyr, hwy_dbd, lLyr)
  opts = null
  opts.[CSV Header] = "True"
  ExportView(lLyr + "|", "CSV", output_dir + "/links.csv", , opts)
  DropLayerFromWorkspace(lLyr)

  // Replace \\ with / for the command line calls
  outputRMD = Substitute(outputRMD, "\\", "/", )
  rscriptexe = Substitute(rscriptexe, "\\", "/", )

  // Create a batch file to render the RMD
  batFile = output_dir + "tempbatch.bat"
  bat = OpenFile(batFile,"w")
  // Temporarily add the pandoc binaries to the system path
  WriteLine(bat, "set OLDPATH=%PATH%")
  WriteLine(bat,"set PATH=%PATH%;" + pandoc_dir)
  // "Rscript -e" allows you to execute R from the command line
  command = rscriptexe + " -e " + "rmarkdown::render('" + outputRMD + "')"
  WriteLine(bat,command)
  // Set the system path back to what it was
  WriteLine(bat, "set PATH = %OLDPATH%")
  CloseFile(bat)

  // Run the batch file
  opts = null
  opts.Minimize = "True"
  ret = RunProgram(batFile,opts)
  if ret <> 0 then do
      ShowMessage("Assignment validation did not run sucessfully.")
      ShowMessage(1)
  end

  // Delete the temp batch file and link.csv/dcc
  DeleteFile(batFile)
  DeleteFile(output_dir + "/links.csv")
  DeleteFile(output_dir + "/links.DCC")
EndMacro

/*
This macro summarizes link-level fields into scenario-level statistics.
Summaries include VMT, VHT, space mean speed, and delay.

MacroOpts
  Named array holding all arguments (e.g. MacroOpts.hwy_dbd)

  hwy_dbd
    String
    Full path of the line geographic file of highway links. This should be the
    "loaded" network, such that the assignment results are included.

  output_dir
    String
    Full path of output directory where the final csv will be written

  at_field
    String
    Field name containing area type information
    Defaults to "AreaType"

  ft_field
    String
    Field name containing facility type information
    Defaults to "HCMType"

  summary_fields
    Named array
    Describes the names of the fields to sum up for each metric
    Defaults to {"Flow_Daily", "VMT_Daily", "VHT_Daily", "Delay_Daily"}
*/

Macro "Link Summary by FT and AT" (MacroOpts)

  // Extract arguments from named array
  hwy_dbd = MacroOpts.hwy_dbd
  output_dir = MacroOpts.output_dir
  at_field = MacroOpts.at_field
  ft_field = MacroOpts.ft_field
  summary_fields = MacroOpts.summary_fields

  // Default values
  if at_field = null then at_field = "AreaType"
  if ft_field = null then ft_field = "HCMType"
  if summary_fields = null then do
    summary_fields = {"Flow_Daily", "VMT_Daily", "VHT_Daily", "Delay_Daily"}
  end

  // Argument checks
  if hwy_dbd = null then Throw("'hwy_dbd' not provided")
  if output_dir = null then Throw("'output_dir' not provided")

  // Open the highway link layer and read into a data frame
  {nlyr, llyr} = GetDBLayers(hwy_dbd)
  AddLayerToWorkspace(llyr, hwy_dbd, llyr)
  hwy_df = CreateObject("df")
  opts = null
  opts.view = llyr
  opts.fields = {ft_field, at_field} + summary_fields
  hwy_df.read_view(opts)

  // Summarize by ft and at
  hwy_df.group_by({ft_field, at_field})
  agg = null
  for f = 1 to summary_fields.length do
    agg.(summary_fields[f]) = {"sum"}
  end
  hwy_df.summarize(agg)
  hwy_df.write_csv(output_dir + "/link_summary_by_FT_and_AT.csv")
EndMacro
